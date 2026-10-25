defmodule NetworkDefense.Optimization.NullStrategy do
  @moduledoc """
  Strategy that does nothing.
  """
  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Optimization.Strategy

  defstruct seed: nil

  # Keep strategy state explicit. This strategy retains only the declared seed.
  def new(_graph, params), do: {:ok, %__MODULE__{seed: params.seed}}

  defimpl Strategy, for: __MODULE__ do
    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Null strategy"

    @spec plan?(Strategy.t()) :: boolean()
    def plan?(_strategy), do: false

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: [DefenseAction.t()]
    def rank(_strategy, _action_types, _graph, _budget), do: []
  end
end
