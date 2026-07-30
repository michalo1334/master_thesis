defmodule NetworkDefense.Optimization.SimulatedAnnealingStrategy do
  @moduledoc false

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Optimization.{Budget, SimulationObjective, Strategy}
  alias NetworkDefense.Simulation.Seed
  alias NetworkDefense.Simulations

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

  def new(graph, %{simulation_params: simulation_params}) do
    %__MODULE__{
      initial_attacker_state:
        Simulations.initial_attacker_state(graph, simulation_params.initial_foothold_node_id),
      rules: Simulations.default_rules(),
      run_count: simulation_params.monte_carlo_trials,
      iteration_count: simulation_params.iterations_per_run,
      seed: simulation_seed(simulation_params),
      max_attempts: simulation_params.max_attempts
    }
  end

  defp simulation_seed(%{generate_seed: true}), do: Seed.random()
  defp simulation_seed(%{seed: seed}), do: seed

  defimpl Strategy, for: __MODULE__ do
    @max_steps 100

    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Simulation-informed simulated annealing strategy"

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: [DefenseAction.t()]
    def rank(strategy, action_types, graph, budget) do
      candidates = candidate_actions(action_types, graph)
      plan_size = min(budget, length(candidates))

      if plan_size == 0 do
        []
      else
        random_state = strategy.seed |> Seed.child_seed(0) |> Seed.integer_to_state()
        {initial_plan, random_state} = random_plan(candidates, plan_size, random_state)
        initial_score = score(graph, initial_plan, strategy)
        # ponytail: cap candidate evaluations so interactive optimization remains bounded.
        steps = min(@max_steps, max(20, length(candidates) * 2))

        {best_plan, _best_score, _random_state} =
          anneal(
            graph,
            candidates,
            %{
              current_plan: initial_plan,
              current_score: initial_score,
              best_plan: initial_plan,
              best_score: initial_score
            },
            strategy,
            steps,
            random_state
          )

        best_plan
      end
    end

    defp anneal(
           _graph,
           _candidates,
           state,
           _strategy,
           0,
           random_state
         ),
         do: {state.best_plan, state.best_score, random_state}

    defp anneal(
           graph,
           candidates,
           state,
           strategy,
           steps,
           random_state
         ) do
      {candidate_plan, random_state} = neighbor(state.current_plan, candidates, random_state)
      candidate_score = score(graph, candidate_plan, strategy)
      temperature = max(0.01, steps / @max_steps)
      {sample, random_state} = :rand.uniform_s(random_state)

      accepted? =
        candidate_score <= state.current_score or
          sample < :math.exp((state.current_score - candidate_score) / temperature)

      state =
        if accepted? do
          %{state | current_plan: candidate_plan, current_score: candidate_score}
        else
          state
        end

      state =
        if candidate_score < state.best_score do
          %{state | best_plan: candidate_plan, best_score: candidate_score}
        else
          state
        end

      anneal(
        graph,
        candidates,
        state,
        strategy,
        steps - 1,
        random_state
      )
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

    defp random_plan(candidates, count, random_state) do
      Enum.reduce(1..count, {[], candidates, random_state}, fn _,
                                                               {plan, available, random_state} ->
        {index, random_state} = :rand.uniform_s(length(available), random_state)
        {action, available} = List.pop_at(available, index - 1)
        {[action | plan], available, random_state}
      end)
      |> then(fn {plan, _available, random_state} -> {plan, random_state} end)
    end

    defp neighbor(plan, candidates, random_state) do
      available = candidates -- plan

      case available do
        [] ->
          {plan, random_state}

        _ ->
          {plan_index, random_state} = :rand.uniform_s(length(plan), random_state)
          {candidate_index, random_state} = :rand.uniform_s(length(available), random_state)

          {List.replace_at(plan, plan_index - 1, Enum.at(available, candidate_index - 1)),
           random_state}
      end
    end

    defp score(graph, plan, strategy) do
      plan
      |> Enum.reduce(graph, &DefenseAction.apply(&1, &2))
      |> SimulationObjective.expected_blast_radius(strategy)
    end
  end
end
