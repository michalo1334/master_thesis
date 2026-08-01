defmodule NetworkDefense.Simulations do
  @moduledoc """
  Public context module for working with simulation related aspects
  """
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulation.SimulationReport
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulation.Simulator
  alias NetworkDefense.Simulation.Seed
  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest
  alias OpentelemetryProcessPropagator.Task.Supervisor, as: TaskSupervisor

  import Ecto.Query

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @simulation_events_topic "simulation_events"
  @trial_batch_size 100
  @report_timeout 60_000

  def simulation_events_topic, do: @simulation_events_topic

  def run_async(%RunSimulationRequest{} = request) do
    case Graphs.load_revision(request.graph_revision_id) do
      nil -> {:error, "graph_not_found"}
      {:error, _reason} -> {:error, "invalid_graph"}
      graph -> run_async(graph, request.correlation_id, request.simulation_params)
    end
  end

  def run_async(graph, correlation_id, simulation_params) do
    with :ok <- validate_initial_foothold(graph, simulation_params.initial_foothold_node_id),
         {:ok, experiment} <- create_experiment(graph, simulation_params) do
      start_async(graph, correlation_id, experiment)
    else
      {:error, reason} ->
        TaskSupervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
          broadcast_simulation_failed(graph, correlation_id, to_string(reason))
        end)
    end
  end

  def resume_async(experiment_id, correlation_id) do
    with {:ok, experiment} <- Experiments.resume(experiment_id),
         %NetworkDefense.Graph.Graph{} = graph <-
           Graphs.load_revision(experiment.graph_revision_id) do
      start_async(graph, correlation_id, experiment)
    else
      nil -> {:error, "graph_not_found"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp start_async(graph, correlation_id, experiment) do
    case TaskSupervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
           try do
             do_run_async(graph, correlation_id, experiment)
           rescue
             error ->
               Experiments.fail(experiment.id)
               Logger.error("Simulation failed: #{Exception.message(error)}")
               broadcast_simulation_failed(graph, correlation_id, Exception.message(error))
           end
         end) do
      {:ok, _pid} = started ->
        started

      {:error, _reason} = error ->
        Experiments.fail(experiment.id)
        error
    end
  end

  defp do_run_async(graph, correlation_id, experiment) do
    Tracer.with_span "simulation.run",
      attributes: %{
        "graph.id": graph.id,
        "correlation.id": correlation_id,
        "simulation.run_count": experiment.total_trials,
        "simulation.iteration_count": experiment.iteration_count
      } do
      experiment = run_batches(graph, correlation_id, experiment)
      Tracer.set_status(OpenTelemetry.status(:ok))
      broadcast_simulation_completed(graph, experiment, correlation_id)
    end
  end

  defp run_batches(graph, correlation_id, experiment) do
    initial_attacker_state = initial_attacker_state(graph, experiment.initial_foothold_node_id)

    (experiment.completed_trials + 1)..experiment.total_trials
    |> Stream.chunk_every(@trial_batch_size)
    |> Enum.reduce(experiment, fn trial_indexes, experiment ->
      {elapsed_us, runs} =
        Tracer.with_span "simulation.compute" do
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

  def parallel_map_fn(enum, fun) do
    TaskSupervisor.async_stream(NetworkDefense.TaskSupervisor, enum, fun,
      ordered: false,
      timeout: :infinity
    )
  end

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

  def list_experiments(graph_revision_id), do: list_experiments([graph_revision_id])

  @doc """
  Returns a generated report for an experiment, or `nil` when it does not exist.
  """
  @spec get_report(String.t()) :: SimulationReport.t() | nil
  def get_report(experiment_id) do
    case load_for_report(experiment_id) do
      nil -> nil
      experiment -> SimulationReport.generate(experiment)
    end
  end

  def initial_attacker_state(graph, foothold_id) when is_binary(foothold_id) do
    case validate_initial_foothold(graph, foothold_id) do
      :ok -> AttackerState.new(foothold_id)
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  def validate_initial_foothold(graph, foothold_id) when is_binary(foothold_id) do
    case NetworkDefense.Graph.Graph.node(graph, foothold_id) do
      %{type: NetworkDefense.Nodes.Host} -> :ok
      _ -> {:error, "initial foothold must identify a host in the graph"}
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
        graph =
          case Graphs.load_revision(experiment.graph_revision_id) do
            %NetworkDefense.Graph.Graph{} = graph -> graph
            _ -> nil
          end

        experiment
        |> Map.put(:graph, graph)
        |> load_report_runs()
    end
  end

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
