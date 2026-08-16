defmodule NetworkDefense.Simulations do
  @moduledoc """
  Public context module for working with simulation related aspects
  """
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Repo
  alias NetworkDefense.Rules.Rule
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulation.SimulationReport
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulation.Simulator
  alias NetworkDefense.Simulation.Seed
  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest
  alias NetworkDefense.Simulation.Contracts.SimulationParams
  alias NetworkDefense.Simulations.Errors
  alias OpentelemetryProcessPropagator.Task.Supervisor, as: TaskSupervisor

  import Ecto.Query

  require OpenTelemetry.Tracer, as: Tracer
  require Logger

  @simulation_events_topic "simulation_events"
  @trial_batch_size 500
  @report_timeout 60_000

  @type async_result :: {:ok, pid()} | {:error, Errors.error()}

  @spec simulation_events_topic() :: String.t()
  def simulation_events_topic, do: @simulation_events_topic

  @spec run_async(RunSimulationRequest.t()) :: async_result()
  def run_async(%RunSimulationRequest{} = request) do
    with {:ok, {graph, experiment}} <-
           prepare_experiment(request.graph_revision_id, request.simulation_params, nil) do
      start_async(graph, request.correlation_id, experiment)
    end
  end

  @spec prepare(Ecto.UUID.t(), SimulationParams.t()) ::
          {:ok, Experiment.t()} | {:error, Errors.error()}
  def prepare(graph_revision_id, %SimulationParams{} = simulation_params) do
    prepare(graph_revision_id, simulation_params, nil)
  end

  @spec prepare(Ecto.UUID.t(), SimulationParams.t(), Ecto.UUID.t() | nil) ::
          {:ok, Experiment.t()} | {:error, Errors.error()}
  def prepare(graph_revision_id, %SimulationParams{} = simulation_params, analysis_id)
      when is_nil(analysis_id) or is_binary(analysis_id) do
    with {:ok, {_graph, experiment}} <-
           prepare_experiment(graph_revision_id, simulation_params, analysis_id) do
      {:ok, experiment}
    end
  end

  @spec run_or_resume(Ecto.UUID.t(), String.t()) :: {:ok, Experiment.t()} | {:error, term()}
  def run_or_resume(experiment_id, correlation_id) do
    case Experiments.resume_or_load(experiment_id) do
      {:ok, %Experiment{status: "completed"} = experiment} -> {:ok, experiment}
      {:ok, experiment} -> run_resumed_experiment(experiment, correlation_id)
      error -> error
    end
  end

  defp prepare_experiment(graph_revision_id, simulation_params, analysis_id)
       when is_binary(graph_revision_id) do
    with {:ok, graph} <- load_graph(graph_revision_id),
         {:ok, experiment} <- prepare_experiment(graph, simulation_params, analysis_id) do
      {:ok, {graph, experiment}}
    end
  end

  defp prepare_experiment(%Graph{} = graph, simulation_params, analysis_id) do
    with :ok <- validate_initial_foothold(graph, simulation_params.initial_foothold_node_id),
         {:ok, experiment} <- create_experiment(graph, simulation_params, analysis_id) do
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

  defp start_async(graph, correlation_id, experiment) do
    case TaskSupervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
           run_experiment(graph, correlation_id, experiment)
         end) do
      {:ok, _pid} = started ->
        started

      {:error, reason} ->
        Logger.error("Unable to start simulation task: #{inspect(reason)}")
        Experiments.fail(experiment.id)
        {:error, :task_unavailable}
    end
  end

  defp run_experiment(graph, correlation_id, experiment) do
    Tracer.with_span "simulation.run",
      attributes: %{
        "graph.id": graph.id,
        "graph.revision_id": graph.revision_id,
        "simulation.experiment_id": experiment.id,
        "correlation.id": correlation_id,
        "simulation.run_count": experiment.total_trials,
        "simulation.iteration_count": experiment.iteration_count,
        "simulation.max_attempts": experiment.max_attempts
      } do
      Logger.debug("Simulation started",
        event: "simulation.run.started",
        experiment_id: experiment.id,
        graph_id: graph.id,
        graph_revision_id: graph.revision_id,
        correlation_id: correlation_id,
        run_count: experiment.total_trials,
        iteration_count: experiment.iteration_count
      )

      try do
        experiment = run_batches(graph, correlation_id, experiment)
        Tracer.set_attributes(%{"simulation.completed_run_count": experiment.completed_trials})
        Tracer.set_status(OpenTelemetry.status(:ok))

        Logger.debug("Simulation completed",
          event: "simulation.run.completed",
          experiment_id: experiment.id,
          graph_id: graph.id,
          graph_revision_id: graph.revision_id,
          correlation_id: correlation_id,
          completed_run_count: experiment.completed_trials,
          runtime_ms: experiment.runtime_ms
        )

        broadcast_simulation_completed(graph, experiment, correlation_id)
        {:ok, experiment}
      rescue
        error ->
          simulation_failure(graph, correlation_id, experiment, error, __STACKTRACE__)
      end
    end
  end

  defp run_resumed_experiment(experiment, correlation_id) do
    case Graphs.load_revision(experiment.graph_revision_id) do
      %Graph{} = graph -> run_experiment(graph, correlation_id, experiment)
      nil -> {:error, :not_found}
      _ -> {:error, :invalid_graph}
    end
  end

  defp simulation_failure(graph, correlation_id, experiment, error, stacktrace) do
    Tracer.record_exception(error, stacktrace)
    Tracer.set_status(OpenTelemetry.status(:error))
    Logger.error(Exception.format(:error, error, stacktrace))
    Experiments.fail(experiment.id)
    broadcast_simulation_failed(graph, correlation_id, :internal_error)
    {:error, :internal_error}
  end

  defp run_batches(graph, correlation_id, experiment) do
    graph = MaterializeReachability.materialize(graph)

    initial_attacker_state = initial_attacker_state(graph, experiment.initial_foothold_node_id)

    (experiment.completed_trials + 1)..experiment.total_trials
    |> Stream.chunk_every(@trial_batch_size)
    |> Enum.reduce(experiment, fn trial_indexes, experiment ->
      {first_trial_index, last_trial_index} = Enum.min_max(trial_indexes)

      {elapsed_us, runs} =
        Tracer.with_span "simulation.compute",
          attributes: %{
            "simulation.batch_size": length(trial_indexes),
            "simulation.first_trial_index": first_trial_index,
            "simulation.last_trial_index": last_trial_index
          } do
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

      runtime_ms = div(elapsed_us, 1000)

      :telemetry.execute(
        [:network_defense, :simulator, :run],
        %{duration: System.convert_time_unit(elapsed_us, :microsecond, :native)},
        %{}
      )

      case Experiments.append_batch(experiment, runs, runtime_ms) do
        {:ok, saved} ->
          Logger.debug("Simulation batch completed",
            event: "simulation.batch.completed",
            experiment_id: saved.id,
            completed_run_count: saved.completed_trials,
            total_run_count: saved.total_trials,
            first_trial_index: first_trial_index,
            last_trial_index: last_trial_index,
            runtime_ms: runtime_ms
          )

          broadcast_simulation_progress(
            graph,
            correlation_id,
            saved.completed_trials,
            saved.total_trials
          )

          saved

        {:error, reason} ->
          raise "Failed to persist simulation batch: #{inspect(reason)}"
      end
    end)
    |> complete_experiment()
  end

  defp complete_experiment(experiment) do
    case Experiments.complete(experiment) do
      {:ok, completed} -> completed
      {:error, reason} -> raise "Failed to complete simulation: #{inspect(reason)}"
    end
  end

  defp create_experiment(graph, simulation_params, analysis_id) do
    seed = if simulation_params.generate_seed, do: Seed.random(), else: simulation_params.seed

    Experiment.new(
      graph_revision_id: graph.revision_id,
      analysis_id: analysis_id,
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
    TaskSupervisor.async_stream(NetworkDefense.TaskSupervisor, enum, fun,
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
  @spec get_report(Ecto.UUID.t()) :: SimulationReport.t() | nil
  def get_report(experiment_id) do
    case load_for_report(experiment_id) do
      nil -> nil
      experiment -> SimulationReport.generate(experiment)
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
         completed_runs: completed_runs,
         total_runs: total_runs
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
