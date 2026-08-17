defmodule NetworkDefense.Optimization.SimulationInformedStrategy do
  @moduledoc false

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Optimization.{Budget, SimulationObjective, SimulationStrategy, Strategy}

  defstruct [
    :initial_attacker_state,
    :rules,
    :run_count,
    :iteration_count,
    :seed,
    max_attempts: 1
  ]

  @type t :: %__MODULE__{
          initial_attacker_state: AttackerState.t(),
          rules: [module() | struct()],
          run_count: pos_integer(),
          iteration_count: pos_integer(),
          seed: non_neg_integer(),
          max_attempts: pos_integer()
        }

  def new(graph, params), do: SimulationStrategy.new(__MODULE__, graph, params)

  defimpl Strategy, for: __MODULE__ do
    @infeasible_score {1.0e9, 1.0e9}

    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Simulation-informed greedy strategy"

    @spec plan?(Strategy.t()) :: boolean()
    def plan?(_strategy), do: false

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: [DefenseAction.t()]
    def rank(strategy, action_types, graph, _budget) do
      candidates = SimulationStrategy.candidate_actions(action_types, graph)

      case candidates do
        [] ->
          []

        _ ->
          baseline = SimulationObjective.expected(graph, strategy)

          # ponytail: evaluate every candidate directly; add pruning or parallelism only after profiling.
          candidates
          |> Enum.map(&score_candidate(&1, graph, strategy))
          |> Enum.filter(fn {_action, score} -> score < baseline end)
          |> Enum.sort_by(fn {action, score} ->
            {score, DefenseAction.cost(action), target_id(action)}
          end)
          |> Enum.map(&elem(&1, 0))
      end
    end

    defp score_candidate(action, graph, strategy) do
      graph = DefenseAction.apply(action, graph)

      if SimulationObjective.feasible?(graph) do
        {action, SimulationObjective.expected(graph, strategy)}
      else
        {action, @infeasible_score}
      end
    end

    defp target_id(action), do: action |> DefenseAction.target() |> elem(1)
  end
end
