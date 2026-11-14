defmodule NetworkDefense.Actions.AttemptedAction do
  @moduledoc """
  Converts action structs to stored attacker-state attempts.
  """

  alias NetworkDefense.Actions.Registry
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.AttackerState.AttemptedAction, as: StoredAttempt

  @spec new(struct()) :: StoredAttempt.t()
  def new(%module{} = action) do
    StoredAttempt.new(
      Registry.type_for!(module),
      Ecto.embedded_dump(action, :json)
    )
  end

  @spec action(StoredAttempt.t()) :: map()
  def action(%StoredAttempt{action_type: type, action_data: data}) do
    case Registry.module_for(type) do
      nil -> raise ArgumentError, "unknown attempted action type"
      module -> Ecto.embedded_load(module, data, :json)
    end
  end

  def attempted?(state, action), do: AttackerState.attempted?(state, new(action))

  def can_attempt?(state, action, max_attempts),
    do: AttackerState.can_attempt?(state, new(action), max_attempts)

  def attempted_action(state, action),
    do: AttackerState.attempted_action(state, new(action))

  def mark_attempted(state, action, max_attempts),
    do: AttackerState.mark_attempted(state, new(action), max_attempts)
end
