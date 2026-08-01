defmodule NetworkDefense.Optimizations do
  @moduledoc """
  Public context module for working with optimization related aspects
  """

  alias Ecto.Changeset
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Optimization.Contracts.RunOptimizationRequest
  alias NetworkDefense.Optimization.CvssStrategy
  alias NetworkDefense.Optimization.Optimizer
  alias NetworkDefense.Optimization.Report
  alias NetworkDefense.Optimization.SimulatedAnnealingStrategy
  alias NetworkDefense.Optimization.SimulationInformedStrategy
  alias NetworkDefense.Optimization.TopologySegmentationStrategy
  alias OpentelemetryProcessPropagator.Task.Supervisor, as: TaskSupervisor

  require Logger

  @optimization_events_topic "optimization_events"
  @strategy_modules %{
    "cvss" => CvssStrategy,
    "simulation_informed" => SimulationInformedStrategy,
    "topology_segmentation" => TopologySegmentationStrategy,
    "simulated_annealing" => SimulatedAnnealingStrategy
  }

  def optimization_events_topic, do: @optimization_events_topic

  def run_async(%RunOptimizationRequest{} = request) do
    case Graphs.load_revision(request.graph_revision_id) do
      nil -> {:error, "graph_not_found"}
      {:error, _reason} -> {:error, "invalid_graph"}
      graph -> start_optimization(graph, request)
    end
  end

  defp start_optimization(graph, request) do
    with {:ok, strategy} <- strategy_for(graph, request) do
      TaskSupervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
        try do
          {runtime_us, result} =
            :timer.tc(fn ->
              Optimizer.apply(graph, strategy, request.optimization_params.budget, fn completed,
                                                                                      total,
                                                                                      phase ->
                broadcast_progress(graph, request.correlation_id, completed, total, phase)
              end)
            end)

          report =
            Report.build(
              graph,
              request.optimization_params.strategy,
              request.optimization_params.budget,
              result,
              runtime_us
            )

          persist_and_broadcast(result.graph, graph, request, report)
        rescue
          error ->
            Logger.error("Optimization failed: #{Exception.message(error)}")
            broadcast_failed(graph, request.correlation_id, Exception.message(error))
        end
      end)
    end
  end

  defp strategy_for(graph, %RunOptimizationRequest{optimization_params: params}) do
    case Map.fetch(@strategy_modules, params.strategy) do
      {:ok, strategy_module} -> strategy_module.new(graph, params)
      :error -> {:error, "unknown_strategy"}
    end
  end

  defp persist_and_broadcast(optimized_graph, graph, request, report) do
    case Graphs.append_optimization(optimized_graph) do
      {:ok, persisted_graph} ->
        Phoenix.PubSub.broadcast(
          NetworkDefense.PubSub,
          @optimization_events_topic,
          {:optimization_completed,
           %{
             correlation_id: request.correlation_id,
             graph_id: graph.id,
             graph_revision_id: persisted_graph.revision_id,
             report: report
           }}
        )

      {:error, reason} ->
        broadcast_failed(graph, request.correlation_id, persistence_error(reason))
    end
  end

  defp persistence_error({:graph, changeset}) do
    changeset
    |> Changeset.traverse_errors(fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, message ->
        String.replace(message, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{field |> Atom.to_string() |> String.capitalize()} #{Enum.join(messages, ", ")}"
    end)
  end

  defp persistence_error(reason), do: inspect(reason)

  defp broadcast_failed(graph, correlation_id, reason) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @optimization_events_topic,
      {:optimization_failed,
       %{
         correlation_id: correlation_id,
         graph_id: graph.id,
         graph_revision_id: graph.revision_id,
         reason: reason
       }}
    )
  end

  defp broadcast_progress(graph, correlation_id, completed_steps, total_steps, phase) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @optimization_events_topic,
      {:optimization_progress,
       %{
         correlation_id: correlation_id,
         graph_id: graph.id,
         graph_revision_id: graph.revision_id,
         completed_steps: completed_steps,
         total_steps: total_steps,
         phase: phase
       }}
    )
  end
end
