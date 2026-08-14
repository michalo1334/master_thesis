defmodule NetworkDefense.Simulation.Simulator do
  @moduledoc """
  Monte Carlo simulation of hypothethical attack on networked services.

  Runs N successive iterations, with each iteration evaluating a set of rules and performing probalistically one selected action.

   The entrypoint function executes multiple runs to produce blast-radius statistics.
  """
  require OpenTelemetry.Tracer, as: Tracer

  alias NetworkDefense.Rules.Rule
  alias NetworkDefense.Actions.Action
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Seed, as: Seed

  @doc """
  Runs a Monte Carlo experiment against graph with supplied options.

  Options:
   - run_count - number of simulation runs
   - seed - master seed from which child seeds are derived
   - iteration_count - iterations per run
   - rules - rule set to evaluate
   - max_attempts - maximum number of attempts per action
   - map_fn - mapping function that maps each run to its result
   - progress_callback - optional fn/2 called after each completed run as `callback(completed, total)`


   Returns a tuple `{experiment, runs}` where `experiment` is the parent record
   linking all completed runs.
  """
  @spec run_experiment(term(), term(), keyword()) :: {Experiment.t(), list(Run.t())}
  def run_experiment(graph, initial_attacker_state, opts) do
    seed = Keyword.get(opts, :seed)
    run_count = Keyword.get(opts, :run_count)
    iteration_count = Keyword.get(opts, :iteration_count)
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    experiment =
      Experiment.new(
        graph_revision_id: graph.revision_id,
        master_seed: seed,
        iteration_count: iteration_count,
        max_attempts: max_attempts,
        total_trials: run_count
      )

    runs = run_batch(experiment, graph, initial_attacker_state, 1..run_count, opts)

    {%{experiment | runs: runs}, runs}
  end

  @doc false
  @spec run_batch(Experiment.t(), term(), term(), Enumerable.t(), keyword()) :: list(Run.t())
  def run_batch(experiment, graph, initial_attacker_state, trial_indexes, opts) do
    map_fn = Keyword.get(opts, :map_fn, &Enum.map/2)

    trial_indexes
    |> map_fn.(fn index ->
      Tracer.with_span "simulation.trial",
        attributes: %{"simulation.trial_index": index} do
        run_single(graph, initial_attacker_state, experiment, opts, index)
      end
    end)
    |> Enum.map(fn
      {:ok, run} -> run
      run -> run
    end)
  end

  def run_single(graph, initial_attacker_state, experiment, opts, index) do
    seed = Seed.child_seed(experiment.master_seed, index)

    run =
      Run.new(
        graph: graph,
        seed: seed,
        trial_index: index,
        initial_attacker_state: initial_attacker_state,
        rules: Keyword.fetch!(opts, :rules),
        experiment_id: experiment.id
      )

    do_run_iteration(experiment, run, Seed.integer_to_state(seed), 1)
  end

  defp do_run_iteration(%Experiment{iteration_count: max_index}, run_state, _random_state, index)
       when index > max_index,
       do: run_state

  defp do_run_iteration(experiment, run_state, random_state, index) do
    case get_possible_actions(run_state)
         |> Enum.filter(
           &AttackerState.can_attempt?(
             Run.current_attacker_state(run_state),
             &1,
             experiment.max_attempts
           )
         )
         |> sort_actions() do
      [] ->
        run_state

      actions ->
        {action, random_state} = select_action(actions, random_state)

        {success?, random_state, attacker_state} =
          maybe_execute_action(
            action,
            Run.current_attacker_state(run_state),
            random_state,
            experiment.max_attempts
          )

        attempted_action = AttackerState.attempted_action(attacker_state, action)

        iteration =
          IterationStep.new(
            index: index,
            attempted_action: attempted_action,
            success?: success?,
            attacker_state: attacker_state
          )

        do_run_iteration(
          experiment,
          Run.add_iteration_step(run_state, iteration),
          random_state,
          index + 1
        )
    end
  end

  def get_possible_actions(state) do
    state.rules |> Enum.flat_map(&Rule.evaluate(&1, state))
  end

  def maybe_execute_action(action, attacker_state, random_state, max_attempts) do
    {sample, random_state} = :rand.uniform_s(random_state)

    attacker_state = AttackerState.mark_attempted(attacker_state, action, max_attempts)

    if sample <= Action.probability(action) do
      {true, random_state, Action.execute(action, attacker_state)}
    else
      {false, random_state, attacker_state}
    end
  end

  defp select_action(actions, random_state) do
    {index, random_state} = :rand.uniform_s(length(actions), random_state)
    {Enum.at(actions, index - 1), random_state}
  end

  defp sort_actions(actions), do: Enum.sort(actions)
end
