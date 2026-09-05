defmodule NetworkDefense.Simulations do
  @moduledoc """
  Public context module for working with simulation related aspects
  """
  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Compute.{LocalExecutor, SimulationOperation}
  alias NetworkDefense.ReportProgress
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiment.Status
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulation.MissionImpact
  alias NetworkDefense.Simulation.SimulationReport
  alias NetworkDefense.Simulation.Telemetry, as: SimulationTelemetry
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulation.Simulator
  alias NetworkDefense.Simulation.Seed
  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest
  alias NetworkDefense.Simulations.Errors
  alias NetworkDefense.Simulations.SimulationWorker

  import Ecto.Query

  require Status

  @simulation_events_topic "simulation_events"
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

  @spec run(Ecto.UUID.t(), keyword()) :: {:ok, Experiment.t()} | {:error, term()}
  def run(experiment_id, opts) do
    correlation_id = Keyword.fetch!(opts, :correlation_id)

    case Experiments.start_empty(experiment_id) do
      {:ok, %Experiment{status: status} = experiment} when Status.terminal?(status) ->
        {:ok, experiment}

      {:ok, experiment} ->
        run_empty(experiment, correlation_id, opts)

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
    with :ok <-
           Simulator.validate_initial_foothold(graph, simulation_params.initial_foothold_node_id),
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

  defp run_empty(experiment, correlation_id, opts) do
    case load_graph(experiment.graph_revision_id) do
      {:ok, graph} ->
        result =
          try do
            SimulationTelemetry.run(experiment, graph, correlation_id, fn ->
              LocalExecutor.run(SimulationOperation, experiment,
                correlation_id: correlation_id,
                max_concurrency: Keyword.get(opts, :max_concurrency, System.schedulers_online()),
                on_progress: progress_callback(graph, correlation_id, opts)
              )
            end)
          rescue
            exception -> normalize_execution_exception(exception)
          end

        finish_run(result, graph, experiment, correlation_id, opts)

      {:error, _reason} = error ->
        Experiments.fail(experiment.id)
        error
    end
  end

  defp normalize_execution_exception(_exception), do: {:error, :internal_error}

  defp finish_run({:ok, completed}, graph, _experiment, correlation_id, opts) do
    if Keyword.get(opts, :publish_events, false) do
      broadcast_simulation_completed(graph, completed, correlation_id)
    end

    {:ok, completed}
  end

  defp finish_run({:error, _reason}, graph, experiment, correlation_id, opts) do
    Experiments.fail(experiment.id)

    if Keyword.get(opts, :publish_events, false) do
      broadcast_simulation_failed(graph, correlation_id, :internal_error)
    end

    {:error, :internal_error}
  end

  defp progress_callback(graph, correlation_id, opts) do
    on_progress = Keyword.get(opts, :on_progress, fn _progress -> :ok end)

    fn %{completed: completed, total: total} = progress ->
      case on_progress.(progress) do
        {:error, _reason} = error ->
          error

        _result ->
          publish_progress(
            Keyword.get(opts, :publish_events, false),
            graph,
            correlation_id,
            completed,
            total
          )

          :ok
      end
    end
  end

  defp publish_progress(false, _graph, _correlation_id, _completed, _total), do: :ok

  defp publish_progress(true, graph, correlation_id, completed, total) do
    broadcast_simulation_progress(graph, correlation_id, completed, total)
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

  @spec list_experiments([Ecto.UUID.t()]) :: [Experiment.t()]
  def list_experiments(graph_revision_ids) when is_list(graph_revision_ids) do
    query =
      from experiment in Experiment,
        join: revision in assoc(experiment, :graph_revision),
        where: revision.id in ^graph_revision_ids,
        where: experiment.status == :completed,
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
    |> where([experiment], experiment.status == :completed)
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
