defmodule NetworkDefense.Optimizations do
  @moduledoc """
  Public context module for working with optimization related aspects
  """

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Optimization.Contracts.RunOptimizationRequest
  alias NetworkDefense.Optimization.CvssStrategy
  alias NetworkDefense.Optimization.Optimizer
  alias NetworkDefense.Optimization.SimulationInformedStrategy
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.Simulation.Seed
  alias NetworkDefense.Simulations
  alias OpentelemetryProcessPropagator.Task.Supervisor, as: TaskSupervisor

  require Logger

  @optimization_events_topic "optimization_events"

  def optimization_events_topic, do: @optimization_events_topic

  def run_async(%RunOptimizationRequest{} = request) do
    case Graphs.load(request.graph_id) do
      nil -> {:error, "graph_not_found"}
      graph -> start_optimization(graph, request)
    end
  end

  defp start_optimization(graph, request) do
    TaskSupervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
      try do
        strategy = strategy_for(graph, request)

        graph
        |> Optimizer.apply(strategy, request.optimization_params.budget)
        |> clone_optimized_graph(strategy)
        |> persist_and_broadcast(graph, request)
      rescue
        error ->
          Logger.error("Optimization failed: #{Exception.message(error)}")
          broadcast_failed(graph.id, request.correlation_id, Exception.message(error))
      end
    end)
  end

  defp strategy_for(_graph, %RunOptimizationRequest{optimization_params: %{strategy: "cvss"}}),
    do: %CvssStrategy{}

  defp strategy_for(
         graph,
         %RunOptimizationRequest{optimization_params: %{strategy: "simulation_informed"} = params}
       ) do
    simulation_params = params.simulation_params

    %SimulationInformedStrategy{
      initial_attacker_state:
        Simulations.initial_attacker_state(graph, simulation_params.initial_foothold_node_id),
      rules: Simulations.default_rules(),
      run_count: simulation_params.monte_carlo_trials,
      iteration_count: simulation_params.iterations_per_run,
      seed: simulation_seed(simulation_params),
      max_attempts: simulation_params.max_attempts
    }
  end

  defp simulation_seed(%{generate_seed: true}), do: Seed.random()
  defp simulation_seed(%{seed: seed}), do: seed

  defp clone_optimized_graph(%Graph{} = graph, strategy) do
    Graph.clone(%{graph | title: "#{graph.title} (optimized with #{Strategy.name(strategy)})"})
  end

  defp persist_and_broadcast(optimized_graph, graph, request) do
    case Graphs.insert(optimized_graph) do
      {:ok, persisted_graph} ->
        Phoenix.PubSub.broadcast(
          NetworkDefense.PubSub,
          @optimization_events_topic,
          {:optimization_completed,
           %{
             correlation_id: request.correlation_id,
             graph_id: graph.id,
             optimized_graph_id: persisted_graph.id
           }}
        )

      {:error, reason} ->
        broadcast_failed(graph.id, request.correlation_id, inspect(reason))
    end
  end

  defp broadcast_failed(graph_id, correlation_id, reason) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @optimization_events_topic,
      {:optimization_failed,
       %{correlation_id: correlation_id, graph_id: graph_id, reason: reason}}
    )
  end
end
