defmodule NetworkDefense.Optimizations do
  @moduledoc """
  Public context module for working with optimization related aspects
  """

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
  alias NetworkDefense.Optimizations.Errors
  alias NetworkDefense.Simulation.MissionImpact
  alias OpentelemetryProcessPropagator.Task.Supervisor, as: TaskSupervisor

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @optimization_events_topic "optimization_events"
  @strategy_modules %{
    "cvss" => CvssStrategy,
    "simulation_informed" => SimulationInformedStrategy,
    "topology_segmentation" => TopologySegmentationStrategy,
    "simulated_annealing" => SimulatedAnnealingStrategy
  }

  @type async_result :: {:ok, pid()} | {:error, Errors.error()}
  @type result :: {:ok, OptimizationRun.t()} | {:error, Errors.error()}

  @spec optimization_events_topic() :: String.t()
  def optimization_events_topic, do: @optimization_events_topic

  @spec set_analysis(Ecto.UUID.t(), Ecto.UUID.t() | nil) ::
          {:ok, OptimizationRun.t()} | {:error, :not_found | :invalid_analysis}
  def set_analysis(run_id, analysis_id), do: OptimizationRuns.set_analysis(run_id, analysis_id)

  @spec run_async(RunOptimizationRequest.t()) :: async_result()
  def run_async(%RunOptimizationRequest{} = request) do
    with {:ok, graph} <- load_graph(request), do: run_async(graph, request)
  end

  @doc """
  Runs an optimization synchronously through the same persistence pipeline as
  `run_async/1`, returning the completed run (or an error tuple).
  """
  @spec run(RunOptimizationRequest.t()) :: result()
  def run(%RunOptimizationRequest{} = request) do
    with {:ok, run} <- prepare(request), do: run_or_resume(run.id, request)
  end

  @spec prepare(RunOptimizationRequest.t()) :: result()
  def prepare(%RunOptimizationRequest{} = request) do
    prepare(request, nil)
  end

  @spec prepare(RunOptimizationRequest.t(), Ecto.UUID.t() | nil) :: result()
  def prepare(%RunOptimizationRequest{} = request, analysis_id)
      when is_nil(analysis_id) or is_binary(analysis_id) do
    with {:ok, graph} <- load_graph(request),
         {:ok, strategy} <- strategy_for(graph, request) do
      persist_run(graph, request, strategy, analysis_id)
    end
  end

  @spec run_or_resume(Ecto.UUID.t(), RunOptimizationRequest.t()) :: result()
  def run_or_resume(run_id, %RunOptimizationRequest{} = request) do
    case OptimizationRuns.resume_or_load(run_id) do
      {:ok, %OptimizationRun{status: "completed"} = run} -> {:ok, run}
      {:ok, run} -> run_resumed_optimization(run, request)
      error -> error
    end
  end

  defp load_graph(%RunOptimizationRequest{graph_revision_id: graph_revision_id}) do
    case Graphs.load_revision(graph_revision_id) do
      nil -> {:error, :not_found}
      {:error, _reason} -> {:error, :invalid_graph}
      graph -> ensure_pre_attack_feasible(graph)
    end
  end

  defp ensure_pre_attack_feasible(graph) do
    if MissionImpact.pre_attack_feasible?(graph) do
      {:ok, graph}
    else
      {:error, :infeasible_input}
    end
  end

  defp run_sync(graph, request, run, strategy) do
    Tracer.with_span "optimization.run",
      attributes: optimization_span_attributes(graph, request, run) do
      log_optimization_started(graph, request, run)

      try do
        {runtime_us, result} = :timer.tc(fn -> apply_optimization(graph, request, strategy) end)
        result = complete_optimization(graph, request, run, result, runtime_us)
        set_optimization_span_status(result)
        result
      rescue
        error ->
          Tracer.record_exception(error, __STACKTRACE__)
          Tracer.set_status(OpenTelemetry.status(:error))
          {:error, fail_optimization(run, error, __STACKTRACE__)}
      end
    end
  end

  defp run_resumed_optimization(run, request) do
    with {:ok, graph} <- load_graph(request),
         {:ok, strategy} <- strategy_for(graph, request) do
      run_sync(graph, request, run, strategy)
    end
  end

  defp run_async(graph, request) do
    with {:ok, strategy} <- strategy_for(graph, request),
         {:ok, run} <- persist_run(graph, request, strategy, nil) do
      start_optimization(graph, request, run, strategy)
    end
  end

  defp persist_run(graph, request, strategy, analysis_id) do
    run =
      OptimizationRun.new(
        graph_revision_id: graph.revision_id,
        analysis_id: analysis_id,
        strategy: request.optimization_params.strategy,
        requested_budget: request.optimization_params.budget,
        seed: strategy.seed,
        simulation_config: simulation_config(request)
      )

    case OptimizationRuns.create(run) do
      {:ok, run} ->
        {:ok, run}

      {:error, reason} ->
        Logger.error("Unable to persist optimization run: #{inspect(reason)}")
        {:error, :persistence_failed}
    end
  end

  defp simulation_config(%RunOptimizationRequest{optimization_params: %{simulation_params: nil}}),
    do: nil

  defp simulation_config(%RunOptimizationRequest{optimization_params: params}) do
    %{
      monte_carlo_trials: params.simulation_params.monte_carlo_trials,
      iterations_per_run: params.simulation_params.iterations_per_run,
      initial_foothold_node_id: params.simulation_params.initial_foothold_node_id,
      max_attempts: params.simulation_params.max_attempts
    }
  end

  defp start_optimization(graph, request, run, strategy) do
    case TaskSupervisor.start_child(
           NetworkDefense.TaskSupervisor,
           fn -> run_optimization(graph, request, run, strategy) end
         ) do
      {:ok, _pid} = started ->
        started

      {:error, reason} ->
        Logger.error("Unable to start optimization task: #{inspect(reason)}")
        OptimizationRuns.fail(run.id)
        {:error, :task_unavailable}
    end
  end

  defp run_optimization(graph, request, run, strategy) do
    Tracer.with_span "optimization.run",
      attributes: optimization_span_attributes(graph, request, run) do
      log_optimization_started(graph, request, run)

      try do
        {runtime_us, result} = :timer.tc(fn -> apply_optimization(graph, request, strategy) end)
        result = complete_optimization(graph, request, run, result, runtime_us)
        set_optimization_span_status(result)
        result
      rescue
        error ->
          Tracer.record_exception(error, __STACKTRACE__)
          Tracer.set_status(OpenTelemetry.status(:error))
          reason = fail_optimization(run, error, __STACKTRACE__)
          broadcast_failed(graph, request.correlation_id, reason)
          {:error, reason}
      end
    end
  end

  defp fail_optimization(run, error, stacktrace) do
    Logger.error(Exception.format(:error, error, stacktrace))
    OptimizationRuns.fail(run.id)
    :internal_error
  end

  defp apply_optimization(graph, request, strategy) do
    Optimizer.apply(
      graph,
      strategy,
      request.optimization_params.budget,
      &broadcast_progress(graph, request.correlation_id, &1, &2, &3)
    )
  end

  defp optimization_span_attributes(graph, request, run) do
    %{
      "graph.id": graph.id,
      "graph.revision_id": graph.revision_id,
      "optimization.run_id": run.id,
      "correlation.id": request.correlation_id,
      "optimization.strategy": request.optimization_params.strategy,
      "optimization.requested_budget": request.optimization_params.budget
    }
  end

  defp set_optimization_span_status({:ok, _run}), do: Tracer.set_status(OpenTelemetry.status(:ok))

  defp set_optimization_span_status({:error, _reason}),
    do: Tracer.set_status(OpenTelemetry.status(:error))

  defp log_optimization_started(graph, request, run) do
    Logger.debug("Optimization started",
      event: "optimization.run.started",
      optimization_id: run.id,
      graph_id: graph.id,
      graph_revision_id: graph.revision_id,
      correlation_id: request.correlation_id,
      strategy: request.optimization_params.strategy,
      requested_budget: request.optimization_params.budget
    )
  end

  defp strategy_for(graph, %RunOptimizationRequest{optimization_params: params}) do
    case Map.fetch(@strategy_modules, params.strategy) do
      {:ok, strategy_module} -> strategy_module.new(graph, params)
      :error -> {:error, :unknown_strategy}
    end
  end

  defp complete_optimization(graph, request, run, result, runtime_us) do
    case Graphs.append_optimization(result.graph, run.analysis_id, fn persisted_graph ->
           OptimizationRuns.complete(run, %{
             actions: Enum.map(result.actions, &action_attrs/1),
             used_budget: result.budget_used,
             runtime_ms: div(runtime_us, 1000),
             output_graph_revision_id: persisted_graph.revision_id
           })
         end) do
      {:ok, completed_run} ->
        Logger.debug("Optimization completed",
          event: "optimization.run.completed",
          optimization_id: completed_run.id,
          graph_id: graph.id,
          graph_revision_id: graph.revision_id,
          correlation_id: request.correlation_id,
          strategy: completed_run.strategy,
          action_count: length(result.actions),
          used_budget: completed_run.used_budget,
          runtime_ms: completed_run.runtime_ms
        )

        broadcast_completed(graph, request, completed_run)
        {:ok, completed_run}

      {:error, reason} ->
        Logger.error("Unable to persist optimization result: #{inspect(reason)}")
        OptimizationRuns.fail(run.id)
        broadcast_failed(graph, request.correlation_id, :persistence_failed)
        {:error, :persistence_failed}
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

  @spec list_runs([Ecto.UUID.t()]) :: [OptimizationRun.t()]
  def list_runs(graph_revision_ids),
    do: OptimizationRuns.list_by_graph_revisions(graph_revision_ids)

  @doc """
  Regenerates a report for a completed optimization run, or `nil` when it does not exist
  or its actions reference a retired defense action type.
  """
  @spec get_report(Ecto.UUID.t()) :: OptimizationReport.t() | nil
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
         completed: completed_steps,
         total: total_steps,
         detail: phase
       }}
    )
  end
end
