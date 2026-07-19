defmodule NetworkDefense.Simulation.Simulator do
  @moduledoc """
  Monte Carlo simulation of hypothethical attack on networked services.

  Runs N successive iterations, with each iteration evaluating a set of rules and performing probalistically one selected action.

  The entrypoint functions are run/2 and run_multiple/1.

  While run/2 performs single simulator run, run_multiple execute multiple ones in sequence, which enables to obtain more accurate blast radius statistics (mean, min, max, p95 etc.).
  """
  alias NetworkDefense.Rules.Rule
  alias NetworkDefense.Actions.Action
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Simulation.State
  alias NetworkDefense.Simulation.IterationStep

  @default_seed 0
  @default_simulation_count 10

  @doc """
  Runs the simulation multiple times with supplied options.

  Options:
   - simulation_count - number of simulation runs
   - seed - initial seed

  Returns a list whose index is nth simulation and element is final attacker state in given simulation instance.
  """
  @spec run_multiple(keyword()) :: list(AttackerState)
  def run_multiple(opts) do
    seed = Keyword.get(opts, :seed, @default_seed)
    simulation_count = Keyword.get(opts, :simulation_count, @default_simulation_count)

    Enum.map(1..simulation_count, fn idx ->
      run(opts |> Keyword.put(:seed, derive_child_seed(seed, idx)))
    end)
  end

  @doc """
  Runs the simulation with supplied options. Returns final attacker state after all iterations.

  Options:
   - initial_state - the attacker initial state or none
   - iteration_count - n
   - seed - seed that is used during any probabilistic action e.g. selecting or sampling action execution/skip outcome. Provides determinism and simulation reproducability
  """
  def run(opts) do
    state_opts =
      opts
      |> Keyword.take([:graph, :initial_attacker_state, :rules, :iteration_count])
      |> Keyword.put(:initial_seed, Keyword.get(opts, :seed, 0))

    run(State.new(state_opts), opts)
  end

  def run(%State{iteration_count: iteration_count} = initial_state, _opts) do
    Enum.reduce(1..iteration_count, initial_state, fn index, state ->
      perform_iteration(state, index)
    end)
  end

  def perform_iteration(%State{} = state, index) do
    selected_action = get_possible_actions(state) |> select_action(state)

    if is_nil(selected_action) do
      state
    else
      {success?, new_seed, new_attacker_state} =
        maybe_execute_action(
          selected_action,
          State.current_seed(state),
          State.current_attacker_state(state)
        )

      next_iteration =
        IterationStep.new(
          index: index,
          attempted_action: selected_action,
          success?: success?,
          seed: new_seed,
          attacker_state: new_attacker_state
        )

      state |> State.add_iteration_step(next_iteration)
    end
  end

  def get_possible_actions(state) do
    state.rules |> Enum.flat_map(&Rule.evaluate(&1, state))
  end

  def maybe_execute_action(action, seed, attacker_state) do
    seed = seed_state(seed)
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
  @spec select_action(list(Action.t()), State.t()) :: Action.t() | nil
  def select_action([], _state), do: nil

  def select_action(actions, _state) do
    hd(actions)
  end

  defp derive_child_seed(parent_seed, index) when is_integer(parent_seed) and is_integer(index) do
    <<child_seed::unsigned-64, _::binary>> =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary(parent_seed + index)
      )

    rem(child_seed, 9_223_372_036_854_775_807)
  end

  defp seed_part(value), do: rem(value, 2_147_483_646) + 1

  defp seed_state(seed) when is_integer(seed), do: integer_to_seed_state(seed)
  defp seed_state(seed), do: seed

  defp integer_to_seed_state(seed) do
    <<first::unsigned-32, second::unsigned-32, third::unsigned-32, _::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary(seed))

    :rand.seed_s(:exsss, {seed_part(first), seed_part(second), seed_part(third)})
  end
end
