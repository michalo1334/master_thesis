defmodule NetworkDefense.Graph.QueryTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Graph.Query
  alias NetworkDefense.Nodes.Registry, as: NodeRegistry
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry
  alias NetworkDefense.Relationships.Runs

  test "matches the remote service exploitation path and returns bound domain objects" do
    foothold = node("foothold", Host)
    reachable_host = node("reachable-host", Host)
    service = node("service", Service)
    vulnerability = node("vulnerability", Vulnerability)

    reachability = edge("reachability", foothold, service, NetworkReachability)
    runs = edge("runs", reachable_host, service, Runs)
    has_vulnerability = edge("has-vulnerability", service, vulnerability, HasVulnerability)

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

    assert match.foothold == foothold
    assert match.target_host == reachable_host
    assert match.runs == runs
    assert match.to == service
    assert match.vuln == vulnerability
    refute Map.has_key?(match, nil)
  end

  defp graph(nodes, edges) do
    graph = %Graph{id: "graph", nodes: [], adjacency_list: %{}}
    graph = Enum.reduce(nodes, graph, &Graph.add_node(&2, &1))
    Enum.reduce(edges, graph, &Graph.add_edge(&2, &1))
  end

  defp node(id, type) do
    %Node{id: id, graph_id: "graph", type: NodeRegistry.type_for(type), data: %{}}
  end

  defp edge(id, from, to, type) do
    %Edge{
      id: id,
      graph_id: "graph",
      from_id: from.id,
      to_id: to.id,
      type: RelationshipRegistry.type_for(type),
      data: %{}
    }
  end
end
