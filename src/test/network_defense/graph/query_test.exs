defmodule NetworkDefense.Graph.QueryTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Graph.Query
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Registry, as: NodeRegistry
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs

  import NetworkDefense.GraphFixtures, only: [edge: 4, edge: 5, graph: 2]

  test "matches the remote service exploitation path and returns bound domain objects" do
    foothold = node("foothold", Host)
    reachable_host = node("reachable-host", Host)
    service = node("service", Service)
    vulnerability = node("vulnerability", Vulnerability)

    reachability = edge("reachability", foothold, service, NetworkReachability)
    runs = edge("runs", reachable_host, service, Runs)

    has_vulnerability =
      edge("has-vulnerability", service, vulnerability, HasVulnerability, %{
        "required_privilege" => "none",
        "granted_privilege" => "user"
      })

    graph =
      graph([foothold, reachable_host, service, vulnerability], [
        reachability,
        runs,
        has_vulnerability
      ])

    assert [match] =
             Query.match(graph, %{
               start: {:foothold, Host, &(&1.id == foothold.id)},
               hops: [
                 %{via: {nil, NetworkReachability}, to: {:to, Service}},
                 %{via: {nil, HasVulnerability}, to: {:vuln, Vulnerability}}
               ],
               joins: [
                 %{from: {:target_host, Host}, via: {:runs, Runs}, to: {:to, Service}}
               ]
             })

    assert match.foothold == Graph.node(graph, foothold.id)
    assert match.target_host == Graph.node(graph, reachable_host.id)
    assert match.runs == Graph.edge(graph, runs.id)
    assert match.to == Graph.node(graph, service.id)
    assert match.vuln == Graph.node(graph, vulnerability.id)
    refute Map.has_key?(match, nil)
  end

  test "join binds each matched service to its own running host without scanning all hosts" do
    foothold = node("foothold", Host)
    host_count = 40

    {nodes, edges} =
      for index <- 1..host_count, reduce: {[], []} do
        {nodes, edges} ->
          host = node("host-#{index}", Host)
          service = node("service-#{index}", Service)
          vulnerability = node("vulnerability-#{index}", Vulnerability)

          edges = [
            edge("reachability-#{index}", foothold, service, NetworkReachability),
            edge("runs-#{index}", host, service, Runs),
            edge("has-vulnerability-#{index}", service, vulnerability, HasVulnerability, %{
              "required_privilege" => "none",
              "granted_privilege" => "user"
            })
            | edges
          ]

          {[host, service, vulnerability | nodes], edges}
      end

    graph = graph([foothold | nodes], edges)

    matches =
      Query.match(graph, %{
        start: {:foothold, Host, &(&1.id == foothold.id)},
        hops: [
          %{via: {nil, NetworkReachability}, to: {:service, Service}},
          %{via: {nil, HasVulnerability}, to: {:vulnerability, Vulnerability}}
        ],
        joins: [
          %{from: {:target_host, Host}, via: {:runs, Runs}, to: {:service, Service}}
        ]
      })

    assert length(matches) == host_count

    assert Enum.all?(matches, fn match ->
             match?(
               %{target_host: %Node{}, runs: %Edge{}, service: %Node{}, vulnerability: %Node{}},
               match
             )
           end)
  end

  defp node(id, Host) do
    %Node{id: id, graph_id: "graph", type: NodeRegistry.type_for(Host), data: %{"name" => id}}
  end

  defp node(id, Service) do
    %Node{
      id: id,
      graph_id: "graph",
      type: NodeRegistry.type_for(Service),
      data: %{"name" => id, "protocol" => "tcp", "port" => 443}
    }
  end

  defp node(id, Vulnerability) do
    %Node{
      id: id,
      graph_id: "graph",
      type: NodeRegistry.type_for(Vulnerability),
      data: %{"identifier" => id, "cvss" => cvss(), "exploit_probability" => 0.5}
    }
  end

  defp cvss do
    %{
      "attack_vector" => "network",
      "attack_complexity" => "low",
      "privileges_required" => "none",
      "user_interaction" => "none",
      "scope" => "unchanged",
      "confidentiality_impact" => "high",
      "integrity_impact" => "none",
      "availability_impact" => "none"
    }
  end
end
