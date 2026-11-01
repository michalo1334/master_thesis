defmodule NetworkDefense.Optimization.RandomStrategy do
  @moduledoc """
  Uniform random strategy.

  `rank/4` returns a full uniform random permutation of the currently useful
  candidates. The optimizer applies the first candidate it can afford and that
  keeps the mission feasible, so one infeasible candidate does not stop the step.

  Each call derives a child seed from the declared plan seed and the remaining
  budget. Every useful action costs one positive unit, so the remaining budget
  decreases between steps and supplies a fresh draw without protocol state.
  """
  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Optimization.SimulationStrategy
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.Simulation.Seed

  defstruct seed: nil

  # Keep strategy state explicit. This strategy retains only the declared seed.
  def new(_graph, params), do: {:ok, %__MODULE__{seed: params.seed}}

  defimpl Strategy, for: __MODULE__ do
    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Random strategy"

    @spec plan?(Strategy.t()) :: boolean()
    def plan?(_strategy), do: false

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: [DefenseAction.t()]
    def rank(strategy, action_types, graph, remaining_budget) do
      candidates = SimulationStrategy.candidate_actions(action_types, graph)
      state = Seed.integer_to_state(Seed.child_seed(strategy.seed, remaining_budget))

      permutation(candidates, state)
    end

    # Selection with removal: every step picks one element uniformly from the
    # remaining candidates, so all orderings are equally likely.
    defp permutation(candidates, state) do
      candidates
      |> permute(length(candidates), state, [])
      |> Enum.reverse()
    end

    defp permute([], 0, _state, acc), do: acc

    defp permute(remaining, count, state, acc) do
      {index, state} = :rand.uniform_s(count, state)
      {picked, rest} = List.pop_at(remaining, index - 1)

      permute(rest, count - 1, state, [picked | acc])
    end
  end
end
