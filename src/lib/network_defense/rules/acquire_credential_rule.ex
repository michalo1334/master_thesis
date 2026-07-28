defmodule NetworkDefense.Rules.AcquireCredentialRule do
  @moduledoc """
  A foothold with the StoresCredential required privilege gets credential deterministically.
  """

  alias NetworkDefense.Rules.Rule

  defstruct []

  defimpl Rule, for: __MODULE__ do
    alias NetworkDefense.Actions.AcquireCredential
    alias NetworkDefense.AttackerState.AttackerState
    alias NetworkDefense.Graph.Query
    alias NetworkDefense.Nodes.Credential
    alias NetworkDefense.Nodes.Host
    alias NetworkDefense.Relationships.StoresCredential
    alias NetworkDefense.Simulation.Run

    def evaluate(_rule, state) do
      %Run{} = state
      attacker_state = Run.current_attacker_state(state)
      graph = state.graph
      foothold_ids = MapSet.new(AttackerState.foothold_nodes(attacker_state))

      graph
      |> Query.match(%{
        start: {:host, Host, &MapSet.member?(foothold_ids, &1.id)},
        hops: [
          %{via: {:stores_credential, StoresCredential}, to: {:credential, Credential}}
        ]
      })
      |> Enum.filter(&privilege_held?(&1, attacker_state))
      |> Enum.map(&action_for_match/1)
    end

    defp privilege_held?(match, attacker_state) do
      stores_credential = match.stores_credential.data

      AttackerState.has_privilege?(
        attacker_state,
        match.host.id,
        stores_credential.required_privilege
      )
    end

    defp action_for_match(match) do
      %AcquireCredential{
        credential_id: match.credential.id,
        host_id: match.host.id,
        supporting_edge_ids: [match.stores_credential.id]
      }
    end
  end
end
