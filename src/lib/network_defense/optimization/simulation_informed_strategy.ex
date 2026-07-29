defmodule NetworkDefense.Optimization.SimulationInformedStrategy do
  @moduledoc false

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Optimization.{Budget, Strategy}
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulation.Simulator

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

  defimpl Strategy, for: __MODULE__ do
    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Simulation-informed greedy strategy"

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: [DefenseAction.t()]
    def rank(strategy, action_types, graph, _budget) do
      candidates = candidate_actions(action_types, graph)

      case candidates do
        [] ->
          []

        _ ->
          baseline = expected_blast_radius(graph, strategy)

          # ponytail: evaluate every candidate directly; add pruning or parallelism only after profiling.
          candidates
          |> Enum.map(fn action ->
            reduction =
              baseline - expected_blast_radius(DefenseAction.apply(action, graph), strategy)

            {action, reduction / DefenseAction.cost(action)}
          end)
          |> Enum.sort_by(fn {action, reduction} -> {-reduction, target_id(action)} end)
          |> Enum.map(&elem(&1, 0))
      end
    end

    defp candidate_actions(action_types, graph) do
      Enum.flat_map(action_types, fn action_type ->
        action = struct!(action_type)
        eligible_types = DefenseAction.eligible_types(action)

        (Graph.nodes(graph) ++ Graph.edges(graph))
        |> Enum.filter(&(&1.type in eligible_types))
        |> Enum.map(&DefenseAction.with_target_id(action, &1.id))
      end)
    end

    defp expected_blast_radius(graph, strategy) do
      {_experiment, runs} =
        Simulator.run_experiment(
          graph,
          strategy.initial_attacker_state,
          run_count: strategy.run_count,
          iteration_count: strategy.iteration_count,
          seed: strategy.seed,
          rules: strategy.rules,
          max_attempts: strategy.max_attempts
        )

      runs
      |> Enum.map(fn run ->
        run |> Run.current_attacker_state() |> AttackerState.foothold_nodes() |> length()
      end)
      |> then(&(Enum.sum(&1) / length(&1)))
    end

    defp target_id(action), do: action |> DefenseAction.target() |> elem(1)
  end
end
