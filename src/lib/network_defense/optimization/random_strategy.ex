defmodule NetworkDefense.Optimization.RandomStrategy do
  @moduledoc """
  Coin flip strategy:
    1. select random action
    2. for this action select random target
    3. return
  """
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Optimization.SimulationStrategy
  alias NetworkDefense.Simulation.Seed
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.DefenseActions.DefenseAction

  defstruct seed: nil

  def new(_graph, params), do: {:ok, %__MODULE__{seed: Map.get(params, :seed)}}

  defimpl Strategy, for: __MODULE__ do
    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Random strategy"

    @spec plan?(Strategy.t()) :: boolean()
    def plan?(_strategy), do: false

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: [DefenseAction.t()]
    def rank(strategy, action_types, graph, _budget) do
      case SimulationStrategy.candidate_actions(action_types, graph) do
        [] ->
          []

        [candidate] ->
          [candidate]

        candidates ->
          {index, _state} =
            :rand.uniform_s(length(candidates), Seed.integer_to_state(strategy.seed || 0))

          [Enum.at(candidates, index - 1)]
      end
    end
  end
end
