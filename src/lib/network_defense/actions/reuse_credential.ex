defmodule NetworkDefense.Actions.ReuseCredential do
  @moduledoc """
  Describes the reuse of a credential to authenticate to a service.
  """
  alias NetworkDefense.Actions.Action

  defstruct [:credential, :source_host, :target_host, :service, :granted_privilege]

  defimpl Action, for: __MODULE__ do
    alias NetworkDefense.AttackerState.AttackerState

    def execute(action, attacker_state) do
      AttackerState.add_foothold(attacker_state, action.target_host.id, action.granted_privilege)
    end

    def probability(_action), do: 1.0

    def key(action),
      do:
        {:reuse_credential, action.credential.id, action.source_host.id, action.target_host.id,
         action.service.id, action.granted_privilege}
  end
end
