defmodule NetworkDefense.Simulations do
  @moduledoc """
  Public context module for working with simulation related aspects
  """
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulation.Simulator
  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest

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
    ctx = OpenTelemetry.Ctx.get_current()

    Task.Supervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
      OpenTelemetry.Ctx.attach(ctx)
      do_run_async(graph, correlation_id, simulation_params, &parallel_map_fn/2)
    end)
  end

  defp do_run_async(graph, correlation_id, simulation_params, map_fun) do
    rules = default_rules()
    run_count = simulation_params.monte_carlo_trials
    iteration_count = simulation_params.iterations_per_run

    Tracer.with_span "simulation.run",
      attributes: %{
        "graph.id": graph.id,
        "correlation.id": correlation_id,
        "simulation.run_count": run_count,
        "simulation.iteration_count": iteration_count
      } do
      try do
        {elapsed_us, {experiment, runs}} =
          Tracer.with_span "simulation.compute" do
            :timer.tc(fn ->
              {experiment, runs} =
                Simulator.run_experiment(
                  graph: graph,
                  run_count: run_count,
                  iteration_count: iteration_count,
                  initial_attacker_state: initial_attacker_state(graph),
                  lock_version: graph.lock_version,
                  rules: rules,
                  map_fun: map_fun
                )

              {experiment, Enum.to_list(runs)}
            end)
            |> then(fn {us, result} ->
              Tracer.set_attributes(%{duration_ms: div(us, 1000)})
              {us, result}
            end)
          end

        runtime_ms = div(elapsed_us, 1000)

        experiment = %{
          experiment
          | runtime_ms: runtime_ms,
            lock_version: graph.lock_version,
            run_count: run_count,
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
      rescue
        e ->
          Tracer.set_status(OpenTelemetry.status(:error, Exception.message(e)))
          Tracer.record_exception(e, __STACKTRACE__)
          Logger.error("Simulation task crashed: #{inspect(e)}")
          broadcast_simulation_failed(graph.id, correlation_id, Exception.message(e))
      catch
        kind, reason ->
          Tracer.set_status(OpenTelemetry.status(:error, "#{kind}: #{inspect(reason)}"))
          Logger.error("Simulation task exited: #{kind}: #{inspect(reason)}")
          broadcast_simulation_failed(graph.id, correlation_id, "#{kind}: #{inspect(reason)}")
      end
    end
  end

  defp parallel_map_fn(enum, fun) do
    Task.Supervisor.async_stream(NetworkDefense.TaskSupervisor, enum, fun,
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

  defp initial_attacker_state(graph) do
    internet_host =
      graph
      |> NetworkDefense.Graph.Graph.nodes()
      |> Enum.find(fn node ->
        short_type = node.type |> Module.split() |> List.last()
        short_type == "Host" and Map.get(node.data, "name") == "internet"
      end)

    case internet_host do
      nil -> AttackerState.new("internet")
      host -> AttackerState.new(host.id)
    end
  end

  defp default_rules do
    [%NetworkDefense.Rules.RemoteServiceExploitation{}]
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
