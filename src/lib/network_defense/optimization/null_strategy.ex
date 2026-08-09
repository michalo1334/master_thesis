defmodule NetworkDefense.Optimization.NullStrategy do
  @moduledoc """
  Strategy that does nothing.
  """
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Graph.Graph

  defstruct seed: nil

  defimpl Strategy, for: __MODULE__ do
    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Null strategy"

    @spec plan?(Strategy.t()) :: boolean()
    def plan?(_strategy), do: false

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: [DefenseAction.t()]
    def rank(_strategy, _action_types, _graph, _budget), do: []
  end
end
