defmodule NetworkDefense.Optimization.Optimizer do
  @moduledoc false

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.DefenseActions.Registry, as: DefenseActionsRegistry
  alias NetworkDefense.DefenseActions.RevokeCredential
  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.DefenseActions.BlockSegmentReachability
  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Simulation.MissionImpact

  require OpenTelemetry.Tracer, as: Tracer

  @type option ::
          {:progress_callback, (non_neg_integer(), pos_integer(), String.t() -> any())}
          | {:require_pre_attack_feasibility, boolean()}

  @spec apply(Graph.t(), term(), Budget.t(), [option()]) :: map()
  def apply(graph, strategy, budget, opts \\ []) do
    progress_callback = Keyword.get(opts, :progress_callback, fn _, _, _ -> :ok end)
    require_pre_attack_feasibility? = Keyword.get(opts, :require_pre_attack_feasibility, true)

    Tracer.with_span "optimizer.apply",
      attributes: %{
        "graph.id": graph.id,
        "optimization.strategy": Strategy.name(strategy),
        "optimization.requested_budget": budget,
        "optimization.plan_based": Strategy.plan?(strategy),
        "optimization.require_pre_attack_feasibility": require_pre_attack_feasibility?
      } do
      {elapsed_us, result} =
        :timer.tc(fn ->
          do_optimize(graph, strategy, budget, progress_callback, require_pre_attack_feasibility?)
        end)

      :telemetry.execute(
        [:network_defense, :optimizer, :run],
        %{duration: System.convert_time_unit(elapsed_us, :microsecond, :native)},
        %{}
      )

      Tracer.set_attributes(%{
        "optimization.action_count": length(result.actions),
        "optimization.used_budget": result.budget_used
      })

      result
    end
  end

  defp do_optimize(graph, strategy, budget, progress_callback, require_pre_attack_feasibility?) do
    default_actions = [BlockSegmentReachability, PatchVulnerability, RevokeCredential]

    if Strategy.plan?(strategy) do
      optimize_plan(
        graph,
        strategy,
        default_actions,
        budget,
        progress_callback,
        require_pre_attack_feasibility?
      )
    else
      optimize_stepwise(
        graph,
        strategy,
        default_actions,
        budget,
        progress_callback,
        require_pre_attack_feasibility?
      )
    end
  end

  defp optimize_plan(graph, strategy, default_actions, budget, progress_callback, require?) do
    strategy
    |> rank_with_span(default_actions, graph, budget)
    |> Enum.reduce_while({graph, budget, [], 0}, fn action, state ->
      apply_plan_action(action, state, budget, progress_callback, require?)
    end)
    |> then(fn {optimized_graph, _remaining_budget, actions, used_budget} ->
      %{graph: optimized_graph, actions: Enum.reverse(actions), budget_used: used_budget}
    end)
  end

  defp rank_with_span(strategy, default_actions, graph, budget) do
    Tracer.with_span "optimizer.rank",
      attributes: %{"optimization.requested_budget": budget} do
      result = Strategy.rank(strategy, default_actions, graph, budget)
      Tracer.set_attributes(%{"optimization.ranked_count": length(result)})
      result
    end
  end

  defp apply_plan_action(
         action,
         {graph, remaining_budget, actions, used_budget},
         budget,
         progress_callback,
         require?
       ) do
    cost = DefenseAction.cost(action)

    if cost <= remaining_budget do
      step = length(actions) + 1
      progress_callback.(step - 1, budget, "Selecting defense #{step} of #{budget}")

      case apply_plan_action_with_span(action, graph, cost, step, require?) do
        {:ok, optimized_graph} ->
          progress_callback.(step, budget, "Applied defense #{step} of #{budget}")

          {:cont,
           {optimized_graph, remaining_budget - cost, [action | actions], used_budget + cost}}

        :infeasible ->
          {:cont, {graph, remaining_budget, actions, used_budget}}
      end
    else
      {:halt, {graph, remaining_budget, actions, used_budget}}
    end
  end

  defp apply_plan_action_with_span(action, graph, cost, step, require?) do
    Tracer.with_span "optimizer.apply_action",
      attributes: action_span_attributes(action, cost, step) do
      case apply_if_feasible(action, graph, require?) do
        {:ok, optimized_graph} ->
          Tracer.set_attributes(%{"optimization.feasible": true})
          {:ok, optimized_graph}

        :infeasible ->
          Tracer.set_attributes(%{"optimization.feasible": false})
          :infeasible
      end
    end
  end

  defp action_span_attributes(action, cost, step) do
    %{
      "optimization.step_index": step,
      "optimization.action_type": DefenseActionsRegistry.short_type_for(action.__struct__),
      "optimization.action_cost": cost
    }
  end

  defp optimize_stepwise(graph, strategy, default_actions, budget, progress_callback, require?) do
    1..budget
    |> Enum.reduce_while({graph, budget, [], 0}, fn step,
                                                    {graph, remaining_budget, actions,
                                                     used_budget} ->
      progress_callback.(step - 1, budget, "Selecting defense #{step} of #{budget}")

      candidate_actions =
        rank_with_span(strategy, default_actions, graph, remaining_budget)
        |> Enum.reject(fn action -> DefenseAction.cost(action) > remaining_budget end)
        |> Enum.filter(&feasible_after?(&1, graph, require?))

      case candidate_actions do
        [] ->
          {:halt, {graph, remaining_budget, actions, used_budget}}

        [action | _] ->
          cost = DefenseAction.cost(action)
          step = length(actions) + 1

          optimized_graph =
            Tracer.with_span "optimizer.apply_action",
              attributes: action_span_attributes(action, cost, step) do
              DefenseAction.apply(action, graph)
            end

          progress_callback.(step, budget, "Applied defense #{step} of #{budget}")

          {:cont,
           {optimized_graph, remaining_budget - cost, [action | actions], used_budget + cost}}
      end
    end)
    |> then(fn {optimized_graph, _remaining_budget, actions, used_budget} ->
      %{graph: optimized_graph, actions: Enum.reverse(actions), budget_used: used_budget}
    end)
  end

  defp apply_if_feasible(action, graph, false), do: {:ok, DefenseAction.apply(action, graph)}

  defp apply_if_feasible(action, graph, true) do
    optimized_graph = DefenseAction.apply(action, graph)

    if MissionImpact.pre_attack_feasible?(optimized_graph) do
      {:ok, optimized_graph}
    else
      :infeasible
    end
  end

  defp feasible_after?(_action, _graph, false), do: true

  defp feasible_after?(action, graph, true) do
    action
    |> DefenseAction.apply(graph)
    |> MissionImpact.pre_attack_feasible?()
  end
end
