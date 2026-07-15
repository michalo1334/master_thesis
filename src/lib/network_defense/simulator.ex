defmodule NetworkDefense.Simulator do
  @moduledoc """
  Monte Carlo simulation of hypothethical attack on networked services.

  Runs N successive iterations, with each iteration evaluating a set of rules and performing probalistically one selected action.

  The entrypoint functions are run/2 and run_multiple/2.

  While run/2 performs single simulator run, run_multiple execute multiple ones in sequence, which enables to obtain more accurate blast radius statistics (mean, min, max, p95 etc.).
  """
  alias NetworkDefense.Rules.Rule
  alias NetworkDefense.Actions.Action
  alias NetworkDefense.AttackerState.AttackerState

  @default_seed 0
  @default_iteration_count 10_000

  @type t :: %__MODULE__{}

  defstruct [
    :graph,
    :initial_seed,
    :current_seed,
    :attacker_state,
    :rules
  ]

  @doc """
  Runs the simulation multiple times with supplied options.
  """
  def run_multiple(opts) do
  end

  @doc """
  Runs the simulation with supplied options. Returns final attacker state after all iterations.

  Options:
   - initial_state - the attacker initial state or none
   - iteration_count - n
   - seed - seed that is used during any probabilistic action e.g. selecting or sampling action execution/skip outcome. Provides determinism and simulation reproducability
  """
  def run(opts), do: run(%__MODULE__{}, opts)

  def run(%__MODULE__{} = initial_state, opts) do
    iteration_count = Keyword.get(opts, :iteration_count, @default_iteration_count)
    seed = Keyword.get(opts, :seed, @default_seed)

    initial_state = %__MODULE__{initial_state | initial_seed: seed}

    Enum.reduce(1..iteration_count, initial_state, fn index, state ->
      perform_iteration(state, index)
    end)
  end

  def perform_iteration(%__MODULE__{} = state, index) do
    state = %__MODULE__{state | current_seed: derive_child_seed(state.initial_seed, index)}

    case get_possible_actions(state) do
      [] -> state
      actions -> actions |> select_action(state) |> maybe_execute_action(state)
    end
  end

  def get_possible_actions(state) do
    state.rules |> Enum.flat_map(&Rule.evaluate(&1, state))
  end

  def maybe_execute_action(action, %__MODULE__{} = state) do
    {sample, current_seed} = :rand.uniform_s(state.current_seed)

    state = %__MODULE__{
      state
      | current_seed: current_seed,
        attacker_state: AttackerState.mark_attempted(state.attacker_state, Action.key(action))
    }

    if sample <= Action.probability(action) do
      %{state | attacker_state: Action.execute(action, state)}
    else
      state
    end
  end

  @moduledoc """
  Select action to execute for the given iteration.

  Default is to select first one.
  """
  @spec select_action(list(Action.t()), __MODULE__.t()) :: Action.t()
  def select_action(actions, _state) do
    hd(actions)
  end

  defp derive_child_seed(parent_seed, index) when is_integer(parent_seed) and is_integer(index) do
    <<first::unsigned-32, second::unsigned-32, third::unsigned-32, _::binary>> =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary(parent_seed + index)
      )

    :rand.seed_s(:exsss, {seed_part(first), seed_part(second), seed_part(third)})
  end

  defp seed_part(value), do: rem(value, 2_147_483_646) + 1
end
