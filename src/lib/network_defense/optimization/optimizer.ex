defmodule NetworkDefense.Optimization.Optimizer do
  @moduledoc false

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.DefenseActions.RevokeCredential
  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.DefenseActions.BlockReachability
  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.Graph.Graph

  require OpenTelemetry.Tracer, as: Tracer

  @spec apply(Graph.t(), term(), Budget.t()) :: Graph.t()
  def apply(graph, strategy, budget) do
    Tracer.with_span "optimizer.apply" do
      {elapsed_us, optimized_graph} =
        :timer.tc(fn -> do_optimize(graph, strategy, budget) end)

      :telemetry.execute(
        [:network_defense, :optimizer, :run],
        %{duration: System.convert_time_unit(elapsed_us, :microsecond, :native)},
        %{}
      )

      optimized_graph
    end
  end

  defp do_optimize(graph, strategy, budget) do
    default_actions = [BlockReachability, PatchVulnerability, RevokeCredential]

    1..budget
    |> Enum.reduce_while({graph, budget}, fn _step, {graph, remaining_budget} ->
      candidate_actions =
        Strategy.rank(strategy, default_actions, graph, remaining_budget)
        |> Enum.reject(fn action -> DefenseAction.cost(action) > remaining_budget end)

      case candidate_actions do
        [] ->
          {:halt, {graph, remaining_budget}}

        [action | _] ->
          optimized_graph = DefenseAction.apply(action, graph)
          {:cont, {optimized_graph, remaining_budget - DefenseAction.cost(action)}}
      end
    end)
    |> elem(0)
  end
end
