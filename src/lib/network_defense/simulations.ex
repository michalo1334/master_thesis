defmodule NetworkDefense.Simulations do
  @moduledoc """
  Public context module for working with simulation related aspects
  """
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.ReportProgress
  alias NetworkDefense.Repo
  alias NetworkDefense.Rules.Rule
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulation.MissionImpact
  alias NetworkDefense.Simulation.SimulationReport
  alias NetworkDefense.Simulation.Telemetry, as: SimulationTelemetry
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulation.Simulator
  alias NetworkDefense.Simulation.Seed
  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest
  alias NetworkDefense.Simulation.Contracts.SimulationParams
  alias NetworkDefense.Simulations.Errors
  alias NetworkDefense.Simulations.SimulationWorker

  import Ecto.Query

  @simulation_events_topic "simulation_events"
  @trial_batch_size 500
  @report_timeout 60_000

  @type async_result :: {:ok, Oban.Job.t()} | {:error, Errors.error()}

  @spec simulation_events_topic() :: String.t()
  def simulation_events_topic, do: @simulation_events_topic

  @spec run_async(RunSimulationRequest.t()) :: async_result()
  def run_async(%RunSimulationRequest{} = request) do
    with {:ok, {_graph, experiment}} <-
           prepare_experiment(request.graph_revision_id, request.simulation_params) do
      enqueue_simulation(request.correlation_id, experiment)
    end
  end

  @spec prepare(Ecto.UUID.t(), SimulationParams.t()) ::
          {:ok, Experiment.t()} | {:error, Errors.error()}
  def prepare(graph_revision_id, %SimulationParams{} = simulation_params) do
    with {:ok, {_graph, experiment}} <-
           prepare_experiment(graph_revision_id, simulation_params) do
      {:ok, experiment}
    end
  end

  @spec run_or_resume(Ecto.UUID.t(), String.t()) :: {:ok, Experiment.t()} | {:error, term()}
  def run_or_resume(experiment_id, correlation_id) do
    case Experiments.resume_or_load(experiment_id) do
      {:ok, %Experiment{status: status} = experiment} when status in ["completed", "cancelled"] ->
        {:ok, experiment}

      {:ok, experiment} ->
        run_resumed_experiment(experiment, correlation_id)

      error ->
        error
    end
  end

  defp prepare_experiment(graph_revision_id, simulation_params)
       when is_binary(graph_revision_id) do
    with {:ok, graph} <- load_graph(graph_revision_id),
         {:ok, experiment} <- prepare_experiment(graph, simulation_params) do
      {:ok, {graph, experiment}}
    end
  end

  defp prepare_experiment(%Graph{} = graph, simulation_params) do
    with :ok <- validate_initial_foothold(graph, simulation_params.initial_foothold_node_id),
         :ok <- validate_mission_feasibility(graph),
         {:ok, experiment} <- create_experiment(graph, simulation_params) do
      {:ok, experiment}
    else
      {:error, %Ecto.Changeset{}} -> {:error, :persistence_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_graph(graph_revision_id) do
    case Graphs.load_revision(graph_revision_id) do
      nil -> {:error, :not_found}
      {:error, _reason} -> {:error, :invalid_graph}
      graph -> {:ok, graph}
    end
  end

  defp enqueue_simulation(correlation_id, experiment) do
    case OpentelemetryOban.insert(
           SimulationWorker.new(%{
             "experiment_id" => experiment.id,
             "correlation_id" => correlation_id
           })
         ) do
      {:ok, _job} = inserted ->
        inserted

      {:error, reason} ->
        SimulationTelemetry.enqueue_failed(correlation_id, reason)

        Experiments.fail(experiment.id)
        {:error, :task_unavailable}
    end
  end

  defp run_experiment(graph, correlation_id, experiment) do
    try do
      experiment =
        SimulationTelemetry.run(experiment, graph, correlation_id, fn ->
          run_batches(graph, correlation_id, experiment)
        end)

      broadcast_simulation_completed(graph, experiment, correlation_id)
      {:ok, experiment}
    rescue
      error ->
        simulation_failure(graph, correlation_id, experiment, error)
    end
  end

  defp run_resumed_experiment(experiment, correlation_id) do
    case Graphs.load_revision(experiment.graph_revision_id) do
      %Graph{} = graph -> run_experiment(graph, correlation_id, experiment)
      nil -> {:error, :not_found}
      _ -> {:error, :invalid_graph}
    end
  end

  defp simulation_failure(graph, correlation_id, experiment, _error) do
    Experiments.fail(experiment.id)
    broadcast_simulation_failed(graph, correlation_id, :internal_error)
    {:error, :internal_error}
  end

  @spec run_batches(Graph.t(), String.t(), Experiment.t(), (Experiment.t() -> any())) ::
          Experiment.t()
  def run_batches(graph, correlation_id, experiment, on_batch_saved \\ fn _saved -> :ok end) do
    graph = MaterializeReachability.materialize(graph)

    initial_attacker_state = initial_attacker_state(graph, experiment.initial_foothold_node_id)

    (experiment.completed_trials + 1)..experiment.total_trials
    |> Stream.chunk_every(@trial_batch_size)
    |> Enum.reduce(experiment, fn trial_indexes, experiment ->
      {first_trial_index, last_trial_index} = Enum.min_max(trial_indexes)

      {elapsed_us, runs} =
        SimulationTelemetry.compute(experiment, trial_indexes, fn ->
          run_batch_timed(experiment, graph, initial_attacker_state, trial_indexes)
        end)

      runtime_ms = div(elapsed_us, 1000)

      case Experiments.append_batch(experiment, runs, runtime_ms) do
        {:ok, saved} ->
          SimulationTelemetry.batch_completed(
            correlation_id,
            saved,
            first_trial_index,
            last_trial_index,
            runtime_ms
          )

          broadcast_simulation_progress(
            graph,
            correlation_id,
            saved.completed_trials,
            saved.total_trials
          )

          on_batch_saved.(saved)

          saved

        {:error, reason} ->
          raise "Failed to persist simulation batch: #{inspect(reason)}"
      end
    end)
    |> complete_experiment()
  end

  defp run_batch_timed(experiment, graph, initial_attacker_state, trial_indexes) do
    :timer.tc(fn ->
      Simulator.run_batch(
        experiment,
        graph,
        initial_attacker_state,
        trial_indexes,
        rules: default_rules(),
        max_attempts: experiment.max_attempts,
        map_fn: &parallel_map_fn/2
      )
    end)
  end

  defp complete_experiment(experiment) do
    case Experiments.complete(experiment) do
      {:ok, completed} -> completed
      {:error, reason} -> raise "Failed to complete simulation: #{inspect(reason)}"
    end
  end

  defp create_experiment(graph, simulation_params) do
    seed = if simulation_params.generate_seed, do: Seed.random(), else: simulation_params.seed

    Experiment.new(
      graph_revision_id: graph.revision_id,
      master_seed: seed,
      iteration_count: simulation_params.iterations_per_run,
      max_attempts: simulation_params.max_attempts,
      total_trials: simulation_params.monte_carlo_trials,
      initial_foothold_node_id: simulation_params.initial_foothold_node_id
    )
    |> Experiments.create()
  end

  @spec parallel_map_fn(Enumerable.t(), (term() -> term())) :: Enumerable.t()
  def parallel_map_fn(enum, fun) do
    OpentelemetryProcessPropagator.Task.Supervisor.async_stream(
      NetworkDefense.TaskSupervisor,
      enum,
      fun,
      ordered: false,
      timeout: :infinity
    )
  end

  @spec list_experiments([Ecto.UUID.t()]) :: [Experiment.t()]
  def list_experiments(graph_revision_ids) when is_list(graph_revision_ids) do
    query =
      from experiment in Experiment,
        join: revision in assoc(experiment, :graph_revision),
        where: revision.id in ^graph_revision_ids,
        where: experiment.status == "completed",
        order_by: [desc: :inserted_at],
        preload: [:graph_revision]

    Repo.all(query)
  end

  @doc """
  Returns a generated report for an experiment, or `nil` when it does not exist.
  """
  @spec get_report(Ecto.UUID.t(), ReportProgress.progress_callback()) ::
          SimulationReport.t() | nil
  def get_report(experiment_id, on_progress \\ ReportProgress.noop()) do
    case load_for_report(experiment_id) do
      nil -> nil
      experiment -> SimulationReport.generate(experiment, on_progress)
    end
  end

  @spec initial_attacker_state(Graph.t(), Ecto.UUID.t()) :: AttackerState.t()
  def initial_attacker_state(graph, foothold_id) when is_binary(foothold_id) do
    case validate_initial_foothold(graph, foothold_id) do
      :ok ->
        AttackerState.new(foothold_id)

      {:error, _reason} ->
        raise ArgumentError, "initial foothold must identify a host in the graph"
    end
  end

  @spec validate_initial_foothold(Graph.t(), Ecto.UUID.t()) ::
          :ok | {:error, :invalid_initial_foothold}
  def validate_initial_foothold(graph, foothold_id) when is_binary(foothold_id) do
    case NetworkDefense.Graph.Graph.node(graph, foothold_id) do
      %{type: NetworkDefense.Nodes.Host} -> :ok
      _ -> {:error, :invalid_initial_foothold}
    end
  end

  @spec validate_mission_feasibility(Graph.t()) :: :ok | {:error, :infeasible_input}
  def validate_mission_feasibility(graph) do
    if MissionImpact.pre_attack_feasible?(graph) do
      :ok
    else
      {:error, :infeasible_input}
    end
  end

  defp load_report_runs(experiment) do
    runs =
      Run
      |> where([run], run.experiment_id == ^experiment.id)
      |> order_by([run], asc: :trial_index)
      |> Repo.all(timeout: @report_timeout)
      |> Repo.preload(:iterations, timeout: @report_timeout)
      |> Enum.map(fn run ->
        %{run | iterations: Enum.sort_by(run.iterations, & &1.index, :desc)}
      end)

    %{experiment | runs: runs}
  end

  defp load_for_report(experiment_id) do
    Experiment
    |> where([experiment], experiment.status == "completed")
    |> Repo.get(experiment_id)
    |> case do
      nil ->
        nil

      experiment ->
        case Graphs.load_revision(experiment.graph_revision_id) do
          %NetworkDefense.Graph.Graph{} = graph ->
            experiment
            |> Map.put(:graph, graph)
            |> load_report_runs()

          _ ->
            nil
        end
    end
  end

  @spec default_rules() :: [Rule.t()]
  def default_rules do
    [
      %NetworkDefense.Rules.RemoteServiceExploitation{},
      %NetworkDefense.Rules.LocalVulnerabilityExploitation{},
      %NetworkDefense.Rules.AcquireCredentialRule{},
      %NetworkDefense.Rules.ReuseCredentialRule{}
    ]
  end

  defp broadcast_simulation_completed(graph, experiment, correlation_id) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @simulation_events_topic,
      {:simulation_completed,
       %{
         correlation_id: correlation_id,
         graph_id: graph.id,
         graph_revision_id: graph.revision_id,
         experiment_id: experiment.id
       }}
    )
  end

  defp broadcast_simulation_progress(graph, correlation_id, completed_runs, total_runs) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @simulation_events_topic,
      {:simulation_progress,
       %{
         correlation_id: correlation_id,
         graph_id: graph.id,
         graph_revision_id: graph.revision_id,
         completed: completed_runs,
         total: total_runs
       }}
    )
  end

  defp broadcast_simulation_failed(graph, correlation_id, reason) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @simulation_events_topic,
      {:simulation_failed,
       %{
         correlation_id: correlation_id,
         graph_id: graph.id,
         graph_revision_id: graph.revision_id,
         reason: reason
       }}
    )
  end
end
