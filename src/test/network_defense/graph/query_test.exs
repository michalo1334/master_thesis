defmodule NetworkDefense.Graph.QueryTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Graph.Nodes.Host
  alias NetworkDefense.Graph.Query
  alias NetworkDefense.Nodes.Application
  alias NetworkDefense.Nodes.Registry, as: NodeRegistry
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Relationships.HasNetworkLink
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry
  alias NetworkDefense.Relationships.Runs

  test "matches the remote application exploitation path and returns bound domain objects" do
    foothold = node("foothold", Host)
    reachable_host = node("reachable-host", Host)
    application = node("application", Application)
    vulnerability = node("vulnerability", Vulnerability)

    link = edge("link", foothold, reachable_host, HasNetworkLink)
    runs = edge("runs", reachable_host, application, Runs)
    has_vulnerability = edge("has-vulnerability", application, vulnerability, HasVulnerability)

    graph =
      graph([foothold, reachable_host, application, vulnerability], [
        link,
        runs,
        has_vulnerability
      ])

    assert [match] =
             Query.match(graph, %{
               start: {:foothold, Host, &(&1.id == foothold.id)},
               hops: [
                 %{via: {nil, HasNetworkLink}, to: {nil, Host}},
                 %{via: {:runs, Runs}, to: {:to, Application}},
                 %{via: {nil, HasVulnerability}, to: {:vuln, Vulnerability}}
               ]
             })

    assert match.foothold == foothold
    assert match.runs == runs
    assert match.to == application
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
