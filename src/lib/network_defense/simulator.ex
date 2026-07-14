defmodule NetworkDefense.Simulator do
  alias NetworkDefense.Rules.Rule
  alias NetworkDefense.Actions.Action

  @default_seed 0
  @default_iteration_count 10_000

  defstruct [
    :graph,
    :initial_seed,
    :current_seed,
    :attacker_state,
    :rules
  ]

  def run(%__MODULE__{} = initial_state, opts) do
    iteration_count = Keyword.get(opts, :iteration_count, @default_iteration_count)
    seed = Keyword.get(opts, :seed, @default_seed)

    initial_state = %__MODULE__{initial_state | initial_seed: seed}

    Enum.reduce(1..iteration_count, initial_state, &perform_iteration(&1, &2))
  end

  def perform_iteration(%__MODULE__{} = state, index) do
    state = %__MODULE__{state | current_seed: derive_child_seed(state.initial_seed, index)}

    actions = get_possible_actions(state)

    Action.execute(select_action(state, actions), state)
  end

  def get_possible_actions(state) do
    state.rules |> Enum.flat_map(&Rule.evaluate(&1, state))
  end

  @moduledoc """
  Select action to execute for the given iteration.

  Default is to select first one.
  """
  @spec select_action(__MODULE__, list(Action.t())) :: Action.t()
  def select_action(_state, actions) do
    hd(actions)
  end

  defp derive_child_seed(parent_seed, index) when is_integer(parent_seed) and is_integer(index) do
    <<derived::unsigned-64, _::binary>> =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary(parent_seed + index)
      )

    derived
  end
end
