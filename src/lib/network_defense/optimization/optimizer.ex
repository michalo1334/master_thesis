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

    Enum.reduce_while(1..budget, graph, fn budget, graph ->
      # Select one that does not reduce budget below 0
      candidate_actions =
        Strategy.rank(strategy, default_actions, graph, budget)
        |> Enum.reject(fn each -> budget - DefenseAction.cost(each) < 0 end)

      # Apply first one
      case candidate_actions do
        [] -> {:halt, graph}
        [h | _] -> {:cont, DefenseAction.apply(h, graph)}
      end
    end)
  end
end
