defmodule NetworkDefense.Optimizations do
  @moduledoc """
  Public context module for working with optimization related aspects
  """

  alias Ecto.Changeset
  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.DefenseActions.Registry, as: DefenseActionsRegistry
  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Optimization.Contracts.RunOptimizationRequest
  alias NetworkDefense.Optimization.CvssStrategy
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Optimization.Optimizer
  alias NetworkDefense.Optimization.OptimizationReport
  alias NetworkDefense.Optimization.SimulatedAnnealingStrategy
  alias NetworkDefense.Optimization.SimulationInformedStrategy
  alias NetworkDefense.Optimization.TopologySegmentationStrategy
  alias OpentelemetryProcessPropagator.Task.Supervisor, as: TaskSupervisor

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
      graph -> run_async(graph, request)
    end
  end

  defp run_async(graph, request) do
    with {:ok, strategy} <- strategy_for(graph, request) do
      run =
        OptimizationRun.new(
          graph_revision_id: graph.revision_id,
          strategy: request.optimization_params.strategy,
          requested_budget: request.optimization_params.budget
        )

      case OptimizationRuns.create(run) do
        {:ok, run} -> start_optimization(graph, request, run, strategy)
        {:error, reason} -> {:error, persistence_error(reason)}
      end
    end
  end

  defp start_optimization(graph, request, run, strategy) do
    case TaskSupervisor.start_child(
           NetworkDefense.TaskSupervisor,
           fn -> run_optimization(graph, request, run, strategy) end
         ) do
      {:ok, _pid} = started ->
        started

      {:error, reason} ->
        reason = persistence_error(reason)
        OptimizationRuns.fail(run.id)
        {:error, reason}
    end
  end

  defp run_optimization(graph, request, run, strategy) do
    {runtime_us, result} = :timer.tc(fn -> apply_optimization(graph, request, strategy) end)
    complete_optimization(graph, request, run, result, runtime_us)
  end

  defp apply_optimization(graph, request, strategy) do
    Optimizer.apply(
      graph,
      strategy,
      request.optimization_params.budget,
      &broadcast_progress(graph, request.correlation_id, &1, &2, &3)
    )
  end

  defp strategy_for(graph, %RunOptimizationRequest{optimization_params: params}) do
    case Map.fetch(@strategy_modules, params.strategy) do
      {:ok, strategy_module} -> strategy_module.new(graph, params)
      :error -> {:error, "unknown_strategy"}
    end
  end

  defp complete_optimization(graph, request, run, result, runtime_us) do
    case Graphs.append_optimization(result.graph, fn persisted_graph ->
           OptimizationRuns.complete(run, %{
             actions: Enum.map(result.actions, &action_attrs/1),
             used_budget: result.budget_used,
             runtime_ms: div(runtime_us, 1000),
             output_graph_revision_id: persisted_graph.revision_id
           })
         end) do
      {:ok, completed_run} ->
        broadcast_completed(graph, request, completed_run)

      {:error, reason} ->
        reason = persistence_error(reason)
        OptimizationRuns.fail(run.id)
        broadcast_failed(graph, request.correlation_id, reason)
    end
  end

  defp action_attrs(action) do
    {_target_type, target_id} = DefenseAction.target(action)

    %{
      action_type: action |> struct_type() |> DefenseActionsRegistry.short_type_for(),
      target_id: target_id,
      cost: DefenseAction.cost(action)
    }
  end

  defp struct_type(%module{}), do: module

  def list_runs(graph_revision_ids),
    do: OptimizationRuns.list_by_graph_revisions(graph_revision_ids)

  @doc """
  Regenerates a report for a completed optimization run, or `nil` when it does not exist
  or its actions reference a retired defense action type.
  """
  @spec get_report(String.t()) :: OptimizationReport.t() | nil
  def get_report(optimization_run_id) do
    with %OptimizationRun{status: "completed"} = run <- OptimizationRuns.load(optimization_run_id),
         true <- materializable_run?(run),
         %Graph{} = graph <- Graphs.load_revision(run.graph_revision_id) do
      OptimizationReport.generate(run, graph)
    else
      _ -> nil
    end
  end

  defp materializable_run?(%OptimizationRun{actions: actions}) do
    Enum.all?(actions, &DefenseActionsRegistry.module_for_short(&1.action_type))
  end

  defp persistence_error({:graph, changeset}), do: persistence_error(changeset)

  defp persistence_error(%Changeset{} = changeset) do
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

  defp broadcast_completed(graph, request, run) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @optimization_events_topic,
      {:optimization_completed,
       %{
         correlation_id: request.correlation_id,
         graph_id: graph.id,
         graph_revision_id: graph.revision_id,
         output_graph_revision_id: run.output_graph_revision_id,
         optimization_id: run.id
       }}
    )
  end

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
