defmodule NetworkDefense.Actions.AcquireCredential do
  @moduledoc """
  Describes the acquisition of a credential from a host.
  """
  alias NetworkDefense.Actions.Action

  defstruct [:credential, :host]

  defimpl Action, for: __MODULE__ do
    alias NetworkDefense.AttackerState.AttackerState

    def execute(action, attacker_state) do
      AttackerState.add_credential(attacker_state, action.credential.id)
    end

    def probability(_action), do: 1.0

    def key(action), do: {:acquire_credential, action.credential.id, action.host.id}
  end
end
