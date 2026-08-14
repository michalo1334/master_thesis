defmodule NetworkDefense.Optimization.Optimizer do
  @moduledoc false

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.DefenseActions.RevokeCredential
  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.DefenseActions.BlockSegmentReachability
  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.Graph.Graph

  require OpenTelemetry.Tracer, as: Tracer

  @spec apply(Graph.t(), term(), Budget.t(), (non_neg_integer(), pos_integer(), String.t() ->
                                                any())) :: map()
  def apply(graph, strategy, budget, progress_callback \\ fn _, _, _ -> :ok end) do
    Tracer.with_span "optimizer.apply",
      attributes: %{
        "graph.id": graph.id,
        "optimization.strategy": Strategy.name(strategy),
        "optimization.requested_budget": budget,
        "optimization.plan_based": Strategy.plan?(strategy)
      } do
      {elapsed_us, optimized_graph} =
        :timer.tc(fn -> do_optimize(graph, strategy, budget, progress_callback) end)

      :telemetry.execute(
        [:network_defense, :optimizer, :run],
        %{duration: System.convert_time_unit(elapsed_us, :microsecond, :native)},
        %{}
      )

      optimized_graph
    end
  end

  defp do_optimize(graph, strategy, budget, progress_callback) do
    default_actions = [BlockSegmentReachability, PatchVulnerability, RevokeCredential]

    if Strategy.plan?(strategy) do
      optimize_plan(graph, strategy, default_actions, budget, progress_callback)
    else
      optimize_stepwise(graph, strategy, default_actions, budget, progress_callback)
    end
  end

  defp optimize_plan(graph, strategy, default_actions, budget, progress_callback) do
    strategy
    |> Strategy.rank(default_actions, graph, budget)
    |> Enum.reduce_while({graph, budget, [], 0}, fn action,
                                                    {graph, remaining_budget, actions,
                                                     used_budget} ->
      cost = DefenseAction.cost(action)

      if cost <= remaining_budget do
        step = length(actions) + 1
        progress_callback.(step - 1, budget, "Selecting defense #{step} of #{budget}")

        optimized_graph = DefenseAction.apply(action, graph)
        progress_callback.(step, budget, "Applied defense #{step} of #{budget}")

        {:cont,
         {optimized_graph, remaining_budget - cost, [action | actions], used_budget + cost}}
      else
        {:halt, {graph, remaining_budget, actions, used_budget}}
      end
    end)
    |> then(fn {optimized_graph, _remaining_budget, actions, used_budget} ->
      %{graph: optimized_graph, actions: Enum.reverse(actions), budget_used: used_budget}
    end)
  end

  defp optimize_stepwise(graph, strategy, default_actions, budget, progress_callback) do
    1..budget
    |> Enum.reduce_while({graph, budget, [], 0}, fn step,
                                                    {graph, remaining_budget, actions,
                                                     used_budget} ->
      progress_callback.(step - 1, budget, "Selecting defense #{step} of #{budget}")

      candidate_actions =
        Strategy.rank(strategy, default_actions, graph, remaining_budget)
        |> Enum.reject(fn action -> DefenseAction.cost(action) > remaining_budget end)

      case candidate_actions do
        [] ->
          {:halt, {graph, remaining_budget, actions, used_budget}}

        [action | _] ->
          optimized_graph = DefenseAction.apply(action, graph)
          cost = DefenseAction.cost(action)
          progress_callback.(step, budget, "Applied defense #{step} of #{budget}")

          {:cont,
           {optimized_graph, remaining_budget - cost, [action | actions], used_budget + cost}}
      end
    end)
    |> then(fn {optimized_graph, _remaining_budget, actions, used_budget} ->
      %{graph: optimized_graph, actions: Enum.reverse(actions), budget_used: used_budget}
    end)
  end
end
