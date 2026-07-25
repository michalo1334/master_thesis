defmodule NetworkDefense.Rules.ReuseCredentialRule do
  @moduledoc """
  Source foothold with matching reachability to Service and acquired Credential AuthenticatesTo
  Service receives granted privilege on the host running service, deterministic.
  """

  alias NetworkDefense.Rules.Rule

  defstruct []

  defimpl Rule, for: __MODULE__ do
    alias NetworkDefense.Actions.Action
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
      creds = attacker_state.credentials

      graph
      |> Query.match(%{
        start: {:source_host, Host, &MapSet.member?(foothold_ids, &1.id)},
        hops: [
          %{via: {:reachability, NetworkReachability}, to: {:service, Service}}
        ],
        joins: [
          %{from: {:target_host, Host}, via: {nil, Runs}, to: {:service, Service}}
        ]
      })
      |> Enum.filter(&reachability_matches?/1)
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
            credential: cred_match.credential,
            source_host: match.source_host,
            target_host: match.target_host,
            service: match.service,
            granted_privilege: authenticates_to.granted_privilege
          }
        end)
      end)
      |> Enum.reject(&AttackerState.attempted?(attacker_state, Action.key(&1)))
    end

    defp reachability_matches?(match) do
      reachability = match.reachability.data
      service = match.service.data
      NetworkReachability.matches_service?(reachability, service)
    end
  end
end
