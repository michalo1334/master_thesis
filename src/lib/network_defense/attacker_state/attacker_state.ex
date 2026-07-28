defmodule NetworkDefense.AttackerState.AttackerState do
  @moduledoc """
  Tracks the resources currently controlled by an attacker during one simulation.
  """
  use Ecto.Schema

  alias NetworkDefense.Actions.AttemptedAction

  @type t :: %__MODULE__{
          foothold_ids: [String.t()],
          credential_ids: [String.t()],
          privileges: %{String.t() => String.t()},
          attempted_actions: [AttemptedAction.t()]
        }

  @primary_key false
  embedded_schema do
    field :foothold_ids, {:array, :string}, default: []
    field :credential_ids, {:array, :string}, default: []
    field :privileges, :map, default: %{}
    embeds_many :attempted_actions, AttemptedAction
  end

  @privilege_order %{none: 0, user: 1, administrator: 2}

  def new(initial_foothold_id, privilege \\ :user) do
    %__MODULE__{
      foothold_ids: [initial_foothold_id],
      privileges: %{initial_foothold_id => Atom.to_string(privilege)},
      credential_ids: []
    }
  end

  def foothold_nodes(state), do: state.foothold_ids

  def add_foothold(state, host_id) do
    add_foothold(state, host_id, :user)
  end

  def add_foothold(state, host_id, privilege) do
    privilege_str = Atom.to_string(privilege)
    current_privilege_str = Map.get(state.privileges, host_id, "none")

    if privilege_order(privilege_str) > privilege_order(current_privilege_str) do
      %{
        state
        | foothold_ids: Enum.uniq([host_id | state.foothold_ids]),
          privileges: Map.put(state.privileges, host_id, privilege_str)
      }
    else
      %{state | foothold_ids: Enum.uniq([host_id | state.foothold_ids])}
    end
  end

  def privilege_for(state, host_id) do
    Map.get(state.privileges, host_id, "none") |> String.to_existing_atom()
  end

  def has_privilege?(state, host_id, required) do
    current = privilege_for(state, host_id)
    privilege_order(current) >= privilege_order(required)
  end

  def add_credential(state, credential_id) do
    %{state | credential_ids: Enum.uniq([credential_id | state.credential_ids])}
  end

  def has_credential?(state, credential_id) do
    credential_id in state.credential_ids
  end

  def attempted?(state, action) do
    attempt_count(state, action) > 0
  end

  def can_attempt?(state, action, max_attempts) do
    attempt_count(state, action) < max_attempts
  end

  def attempted_action(state, action) do
    Enum.find(state.attempted_actions, fn aa ->
      AttemptedAction.action(aa) == action
    end)
  end

  def mark_attempted(state, action, max_attempts) do
    idx =
      Enum.find_index(state.attempted_actions, fn aa ->
        AttemptedAction.action(aa) == action
      end)

    case idx do
      nil ->
        attempted_action = AttemptedAction.new(action) |> AttemptedAction.increment(max_attempts)
        %{state | attempted_actions: [attempted_action | state.attempted_actions]}

      i ->
        updated =
          List.update_at(state.attempted_actions, i, &AttemptedAction.increment(&1, max_attempts))

        %{state | attempted_actions: updated}
    end
  end

  defp attempt_count(state, action) do
    case attempted_action(state, action) do
      nil -> 0
      attempted_action -> attempted_action.attempt_count
    end
  end

  defp privilege_order(privilege) when is_atom(privilege),
    do: Map.get(@privilege_order, privilege, 0)

  defp privilege_order(privilege) when is_binary(privilege),
    do: Map.get(@privilege_order, String.to_existing_atom(privilege), 0)
end
