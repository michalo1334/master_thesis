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
      # Select random action type from passed list
      action_type = Enum.random(action_types)

      applicable_types = DefenseAction.eligible_types(action_type)

      # If it's applicable to node types, get all nodes of this type
      applicable_nodes =
        Graph.nodes(graph)
        |> Enum.filter(fn each -> Enum.member?(applicable_types, each.type) end)
    end
  end
end
