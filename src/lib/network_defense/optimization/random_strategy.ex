defmodule NetworkDefense.Optimization.RandomStrategy do
  @moduledoc """
  Coin flip strategy:
    1. select random action
    2. for this action select random target
    3. return
  """
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.Actions.Action
  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Graph.Graph

  defstruct []

  defimpl Strategy, for: __MODULE__ do
    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Random strategy"

    @spec rank(Strategy.t(), Graph.t(), Budget.t()) :: list(Action.t())
    def rank(_strategy, _graph, _budget), do: []
  end
end
