defmodule NetworkDefense.Optimization.SimulatedAnnealingStrategy do
  @moduledoc false

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Optimization.{Budget, SimulationObjective, SimulationStrategy, Strategy}
  alias NetworkDefense.Simulation.Seed

  require OpenTelemetry.Tracer, as: Tracer

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
    @max_steps 100
    @infeasible_score {1.0e9, 1.0e9, 1.0e9}

    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Simulation-informed simulated annealing strategy"

    @spec plan?(Strategy.t()) :: boolean()
    def plan?(_strategy), do: true

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: [DefenseAction.t()]
    def rank(strategy, action_types, graph, budget) do
      candidates = SimulationStrategy.candidate_actions(action_types, graph)
      plan_size = min(budget, length(candidates))

      if plan_size == 0 do
        []
      else
        random_state = strategy.seed |> Seed.child_seed(0) |> Seed.integer_to_state()
        {initial_plan, random_state} = random_plan(candidates, plan_size, random_state)
        baseline_score = score(graph, [], strategy)
        initial_score = score(graph, initial_plan, strategy)
        # ponytail: cap candidate evaluations so interactive optimization remains bounded.
        steps = min(@max_steps, max(20, length(candidates) * 2))

        {best_plan, best_score, _random_state, _accepted_count} =
          Tracer.with_span "optimizer.anneal",
            attributes: %{
              "optimization.steps": steps,
              "optimization.plan_size": plan_size,
              "optimization.baseline_score": inspect(baseline_score),
              "optimization.initial_score": inspect(initial_score)
            } do
            {best_plan, best_score, random_state, accepted_count} =
              anneal(
                graph,
                candidates,
                %{
                  current_plan: initial_plan,
                  current_score: initial_score,
                  best_plan: initial_plan,
                  best_score: initial_score,
                  accepted_count: 0
                },
                strategy,
                steps,
                random_state
              )

            Tracer.set_attributes(%{
              "optimization.accepted_count": accepted_count,
              "optimization.best_score": inspect(best_score)
            })

            {best_plan, best_score, random_state, accepted_count}
          end

        if best_score < baseline_score do
          best_plan
        else
          []
        end
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
         do: {state.best_plan, state.best_score, random_state, state.accepted_count}

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
        candidate_score < @infeasible_score and
          (candidate_score <= state.current_score or
             sample <
               :math.exp((energy(state.current_score) - energy(candidate_score)) / temperature))

      state =
        if accepted? do
          %{
            state
            | current_plan: candidate_plan,
              current_score: candidate_score,
              accepted_count: state.accepted_count + 1
          }
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

    defp energy({mission_impact, blast_radius, _cost}), do: mission_impact * 1000 + blast_radius

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
      graph = Enum.reduce(plan, graph, &DefenseAction.apply(&1, &2))

      if SimulationObjective.feasible?(graph) do
        {mission_impact, blast_radius} = SimulationObjective.expected(graph, strategy)
        cost = Enum.sum(Enum.map(plan, &DefenseAction.cost/1))
        {mission_impact, blast_radius, cost}
      else
        @infeasible_score
      end
    end
  end
end
