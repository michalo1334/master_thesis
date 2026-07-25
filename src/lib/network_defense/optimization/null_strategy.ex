defmodule NetworkDefense.Optimization.NullStrategy do
  @moduledoc """
  Strategy that does nothing.
  """
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.Actions.Action
  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Graph.Graph

  defstruct []

  defimpl Strategy, for: __MODULE__ do
    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Null strategy"

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: list(Action.t())
    def rank(_strategy, _action_types, _graph, _budget), do: []
  end
end
