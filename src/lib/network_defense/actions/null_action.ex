defmodule NetworkDefense.Actions.NullAction do
  @moduledoc """
    An action that does nothing (does not modify attacker state)
  """
  alias NetworkDefense.Actions.Action

  defstruct []

  defimpl Action, for: __MODULE__ do
    alias NetworkDefense.Simulator
    def execute(_action, %Simulator{attacker_state: attacker_state}), do: attacker_state

    def probability(_action), do: 1.0
  end
end
