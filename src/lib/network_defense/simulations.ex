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

  def simulation_events_topic, do: @simulation_events_topic

  def run_async(%RunSimulationRequest{} = request) do
    case Graphs.load(request.graph_id) do
      graph when not is_nil(graph) ->
        run_async(graph, request.correlation_id, request.simulation_params)

      nil ->
        {:error, "graph_not_found"}
    end
  end

  def run_async(graph, correlation_id, simulation_params) do
    TaskSupervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
      try do
        do_run_async(graph, correlation_id, simulation_params, &parallel_map_fn/2)
      rescue
        error ->
          Logger.error("Simulation failed: #{Exception.message(error)}")
          broadcast_simulation_failed(graph.id, correlation_id, Exception.message(error))
      end
    end)
  end

  defp do_run_async(graph, correlation_id, simulation_params, map_fun) do
    rules = default_rules()
    run_count = simulation_params.monte_carlo_trials
    iteration_count = simulation_params.iterations_per_run

    initial_attacker_state =
      initial_attacker_state(graph, simulation_params.initial_foothold_node_id)

    seed =
      if simulation_params.generate_seed do
        Seed.random()
      else
        simulation_params.seed
      end

    Tracer.with_span "simulation.run",
      attributes: %{
        "graph.id": graph.id,
        "correlation.id": correlation_id,
        "simulation.run_count": run_count,
        "simulation.iteration_count": iteration_count
      } do
      {elapsed_us, {experiment, runs}} =
        Tracer.with_span "simulation.compute" do
          :timer.tc(fn ->
            {experiment, runs} =
              Simulator.run_experiment(
                graph,
                initial_attacker_state,
                run_count: run_count,
                iteration_count: iteration_count,
                seed: seed,
                lock_version: graph.lock_version,
                rules: rules,
                max_attempts: simulation_params.max_attempts,
                map_fn: map_fun
              )

            {experiment, runs}
          end)
          |> then(fn {us, result} ->
            Tracer.set_attributes(%{duration_ms: div(us, 1000)})
            {us, result}
          end)
        end

      runtime_ms = div(elapsed_us, 1000)

      :telemetry.execute(
        [:network_defense, :simulator, :run],
        %{duration: System.convert_time_unit(elapsed_us, :microsecond, :native)},
        %{}
      )

      experiment = %{
        experiment
        | runtime_ms: runtime_ms,
          lock_version: graph.lock_version,
          runs: runs
      }

      case Experiments.insert(experiment) do
        {:ok, saved} ->
          Tracer.set_status(OpenTelemetry.status(:ok))
          broadcast_simulation_completed(saved, correlation_id)

        {:error, reason} ->
          Tracer.set_status(OpenTelemetry.status(:error, inspect(reason)))
          Logger.error("Failed to persist simulation: #{inspect(reason)}")
          broadcast_simulation_failed(graph.id, correlation_id, inspect(reason))
      end
    end
  end

  def parallel_map_fn(enum, fun) do
    TaskSupervisor.async_stream(NetworkDefense.TaskSupervisor, enum, fun,
      ordered: false,
      timeout: :infinity
    )
  end

  def list_experiments(graph_ids) when is_list(graph_ids) do
    query =
      from experiment in Experiment,
        where: experiment.graph_id in ^graph_ids,
        order_by: [desc: :inserted_at],
        preload: [:graph]

    Repo.all(query)
  end

  def list_experiments(graph_ids), do: list_experiments([graph_ids])

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
    case NetworkDefense.Graph.Graph.node(graph, foothold_id) do
      %{type: NetworkDefense.Nodes.Host} -> AttackerState.new(foothold_id)
      _ -> raise ArgumentError, "initial foothold must identify a host in the graph"
    end
  end

  defp load_report_runs(experiment) do
    runs =
      Run
      |> where([run], run.experiment_id == ^experiment.id)
      |> order_by([run], asc: :inserted_at)
      |> Repo.all()
      |> Repo.preload(:iterations)
      |> Enum.map(fn run ->
        %{run | iterations: Enum.sort_by(run.iterations, & &1.index, :desc)}
      end)

    %{experiment | runs: runs}
  end

  defp load_for_report(experiment_id) do
    Experiment
    |> Repo.get(experiment_id)
    |> case do
      nil ->
        nil

      experiment ->
        experiment |> Map.put(:graph, Graphs.load(experiment.graph_id)) |> load_report_runs()
    end
  end

  defp default_rules do
    [
      %NetworkDefense.Rules.RemoteServiceExploitation{},
      %NetworkDefense.Rules.LocalVulnerabilityExploitation{},
      %NetworkDefense.Rules.AcquireCredentialRule{},
      %NetworkDefense.Rules.ReuseCredentialRule{}
    ]
  end

  defp broadcast_simulation_completed(experiment, correlation_id) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @simulation_events_topic,
      {:simulation_completed,
       %{
         correlation_id: correlation_id,
         graph_id: experiment.graph_id,
         experiment_id: experiment.id
       }}
    )
  end

  defp broadcast_simulation_failed(graph_id, correlation_id, reason) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @simulation_events_topic,
      {:simulation_failed,
       %{
         correlation_id: correlation_id,
         graph_id: graph_id,
         reason: reason
       }}
    )
  end
end
