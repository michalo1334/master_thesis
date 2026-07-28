defmodule NetworkDefense.Actions.AcquireCredential do
  @moduledoc """
  Describes the acquisition of a credential from a host.
  """
  use Ecto.Schema

  alias NetworkDefense.Actions.Action

  @primary_key false
  embedded_schema do
    field :credential_id, :string
    field :host_id, :string
    field :supporting_edge_ids, {:array, :string}, default: []
  end

  defimpl Action, for: __MODULE__ do
    alias NetworkDefense.AttackerState.AttackerState

    def execute(action, attacker_state) do
      AttackerState.add_credential(attacker_state, action.credential_id)
    end

    def probability(_action), do: 1.0
  end
end
