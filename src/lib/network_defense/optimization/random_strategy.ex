defmodule NetworkDefense.Optimization.RandomStrategy do
  @moduledoc """
  Coin flip strategy:
    1. select random action
    2. for this action select random target
    3. return
  """
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.DefenseActions.DefenseAction

  defstruct []

  defimpl Strategy, for: __MODULE__ do
    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Random strategy"

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: [DefenseAction.t()]
    def rank(_strategy, action_types, graph, _budget) do
      candidates =
        Enum.flat_map(action_types, fn action_type ->
          action = struct!(action_type)
          eligible_types = DefenseAction.eligible_types(action)

          (Graph.nodes(graph) ++ Graph.edges(graph))
          |> Enum.filter(&(&1.type in eligible_types))
          |> Enum.map(&DefenseAction.with_target_id(action, &1.id))
        end)

      case candidates do
        [] -> []
        candidates -> [Enum.random(candidates)]
      end
    end
  end
end
