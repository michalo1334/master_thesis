defmodule NetworkDefense.Actions.ReuseCredential do
  @moduledoc """
  Describes the reuse of a credential to authenticate to a service.
  """
  use Ecto.Schema

  alias NetworkDefense.Actions.Action

  @primary_key false
  embedded_schema do
    field :credential_id, :string
    field :source_host_id, :string
    field :target_host_id, :string
    field :service_id, :string
    field :granted_privilege, Ecto.Enum, values: [:none, :user, :administrator]
    field :supporting_edge_ids, {:array, :string}, default: []
  end

  defimpl Action, for: __MODULE__ do
    alias NetworkDefense.AttackerState.AttackerState

    def execute(action, attacker_state) do
      AttackerState.add_foothold(attacker_state, action.target_host_id, action.granted_privilege)
    end

    def probability(_action), do: 1.0
  end
end
