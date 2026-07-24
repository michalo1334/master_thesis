defmodule NetworkDefense.Simulation.Simulator do
  @moduledoc """
  Monte Carlo simulation of hypothethical attack on networked services.

  Runs N successive iterations, with each iteration evaluating a set of rules and performing probalistically one selected action.

   The entrypoint functions are run/2 and run_experiment/1.

   While run/2 performs a single run, run_experiment/1 executes multiple runs in sequence to produce blast-radius statistics.
  """
  alias NetworkDefense.Rules.Rule
  alias NetworkDefense.Actions.Action
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Seed, as: Seed

  @default_run_count 10

  @doc """
   Runs a Monte Carlo experiment with supplied options.

  Options:
    - run_count - number of simulation runs
   - seed - master seed from which child seeds are derived
   - graph - the network graph
   - initial_attacker_state - attacker starting position
   - iteration_count - iterations per run
   - rules - rule set to evaluate
   - map_fn - mapping function that maps each run to its result

   Returns a tuple `{experiment, runs}` where `experiment` is the parent record
   linking all completed runs.
  """
  @spec run_experiment(keyword()) :: {Experiment.t(), list(Run.t())}
  def run_experiment(opts) do
    seed = Keyword.get(opts, :seed)
    run_count = Keyword.get(opts, :run_count, @default_run_count)
    iteration_count = Keyword.get(opts, :iteration_count, 1000)
    lock_version = Keyword.get(opts, :lock_version, 1)
    map_fn = Keyword.get(opts, :map_fn, &Enum.map/2)

    experiment =
      Experiment.new(
        seed: seed,
        iteration_count: iteration_count,
        run_count: run_count,
        lock_version: lock_version,
        graph: Keyword.get(opts, :graph),
        initial_attacker_state: Keyword.get(opts, :initial_attacker_state)
      )

    runs =
      map_fn.(1..run_count, fn idx ->
        run(
          opts
          |> Keyword.put(:seed, Seed.child_seed(seed, idx))
          |> Keyword.put(:experiment_id, experiment.id)
        )
      end)

    {%{experiment | runs: runs}, runs}
  end

  @doc """
   Runs one simulation. Returns the completed Run after all iterations.

  Options:
   - initial_state - the attacker initial state or none
   - iteration_count - n
   - seed - seed that is used during any probabilistic action e.g. selecting or sampling action execution/skip outcome. Provides determinism and simulation reproducability
    - experiment_id - optional parent Experiment id linking this run to its experiment
  """
  def run(opts) do
    state_opts =
      opts
      |> Keyword.take([:graph, :initial_attacker_state, :rules, :iteration_count])
      |> Keyword.put(:initial_seed, Keyword.get(opts, :seed, 0))
      |> then(fn base_opts ->
        case Keyword.get(opts, :experiment_id) do
          nil -> base_opts
          id -> Keyword.put(base_opts, :experiment_id, id)
        end
      end)

    run(Run.new(state_opts), opts)
  end

  def run(%Run{iteration_count: iteration_count} = initial_state, _opts) do
    Enum.reduce(1..iteration_count, initial_state, fn index, state ->
      perform_iteration(state, index)
    end)
  end

  def perform_iteration(%Run{} = state, index) do
    selected_action = get_possible_actions(state) |> select_action(state)

    if is_nil(selected_action) do
      state
    else
      {success?, new_seed, new_attacker_state} =
        maybe_execute_action(
          selected_action,
          Run.current_seed(state),
          Run.current_attacker_state(state)
        )

      next_iteration =
        IterationStep.new(
          index: index,
          attempted_action: selected_action,
          success?: success?,
          seed: new_seed,
          attacker_state: new_attacker_state
        )

      state |> Run.add_iteration_step(next_iteration)
    end
  end

  def get_possible_actions(state) do
    state.rules |> Enum.flat_map(&Rule.evaluate(&1, state))
  end

  def maybe_execute_action(action, seed, attacker_state) do
    seed = Seed.seed_state(seed)
    {sample, new_seed} = :rand.uniform_s(seed)

    new_attacker_state = AttackerState.mark_attempted(attacker_state, Action.key(action))

    if sample <= Action.probability(action) do
      {true, new_seed, Action.execute(action, new_attacker_state)}
    else
      {false, new_seed, new_attacker_state}
    end
  end

  @doc """
  Select action to execute for the given iteration.

  Default is to select first one.
  """
  @spec select_action(list(Action.t()), Run.t()) :: Action.t() | nil
  def select_action([], _state), do: nil

  def select_action(actions, _state) do
    hd(actions)
  end
end
