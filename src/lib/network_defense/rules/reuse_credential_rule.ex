defmodule NetworkDefense.Rules.ReuseCredentialRule do
  @moduledoc """
  Source foothold with reachability to Service and acquired Credential AuthenticatesTo
  Service receives granted privilege on the host running service, deterministic.
  """

  alias NetworkDefense.Rules.Rule

  defstruct []

  defimpl Rule, for: __MODULE__ do
    alias NetworkDefense.Actions.ReuseCredential
    alias NetworkDefense.AttackerState.AttackerState
    alias NetworkDefense.Graph.Query
    alias NetworkDefense.Nodes.Credential
    alias NetworkDefense.Nodes.Host
    alias NetworkDefense.Nodes.Service
    alias NetworkDefense.Relationships.AuthenticatesTo
    alias NetworkDefense.Relationships.NetworkReachability
    alias NetworkDefense.Relationships.Runs
    alias NetworkDefense.Simulation.Run

    def evaluate(_rule, state) do
      %Run{} = state
      attacker_state = Run.current_attacker_state(state)
      graph = state.graph
      foothold_ids = MapSet.new(AttackerState.foothold_nodes(attacker_state))
      creds = MapSet.new(attacker_state.credential_ids)

      graph
      |> Query.match(%{
        start: {:source_host, Host, &MapSet.member?(foothold_ids, &1.id)},
        hops: [
          %{via: {:reachability, NetworkReachability}, to: {:service, Service}}
        ],
        joins: [
          %{from: {:target_host, Host}, via: {:runs, Runs}, to: {:service, Service}}
        ]
      })
      |> Enum.flat_map(fn match ->
        graph
        |> Query.match(%{
          start: {:credential, Credential, &MapSet.member?(creds, &1.id)},
          hops: [
            %{via: {:authenticates_to, AuthenticatesTo}, to: {:svc, Service}}
          ]
        })
        |> Enum.filter(fn cred_match -> cred_match.svc.id == match.service.id end)
        |> Enum.map(fn cred_match ->
          authenticates_to = cred_match.authenticates_to.data

          %ReuseCredential{
            credential_id: cred_match.credential.id,
            source_host_id: match.source_host.id,
            target_host_id: match.target_host.id,
            service_id: match.service.id,
            granted_privilege: authenticates_to.granted_privilege,
            supporting_edge_ids: [
              match.reachability.id,
              match.runs.id,
              cred_match.authenticates_to.id
            ]
          }
        end)
      end)
    end
  end
end
