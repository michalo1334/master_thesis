defmodule NetworkDefense.Optimization.RandomStrategyTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.DefenseActions.{BlockReachability, RevokeCredential}
  alias NetworkDefense.Graph.{Edge, Graph, Node}
  alias NetworkDefense.Nodes.{Credential, Host, Service}
  alias NetworkDefense.Optimization.{RandomStrategy, Strategy}
  alias NetworkDefense.Relationships.NetworkReachability

  test "selects a concrete action for an eligible edge" do
    graph =
      graph(
        [node("host", Host, %{"name" => "host"}), node("service", Service, service_data())],
        [edge("reachability", "host", "service", NetworkReachability, %{"protocol" => "tcp"})]
      )

    assert [%BlockReachability{edge_id: "reachability"}] =
             Strategy.rank(%RandomStrategy{}, [BlockReachability], graph, 1)
  end

  test "selects a credential node for revocation" do
    graph = graph([node("credential", Credential, credential_data())], [])

    assert [%RevokeCredential{credential_id: "credential"}] =
             Strategy.rank(%RandomStrategy{}, [RevokeCredential], graph, 1)
  end

  test "returns no action when no eligible target exists" do
    graph = graph([node("host", Host, %{"name" => "host"})], [])

    assert Strategy.rank(%RandomStrategy{}, [BlockReachability], graph, 1) == []
  end

  test "returns no action when no action type is provided" do
    assert Strategy.rank(%RandomStrategy{}, [], graph([], []), 1) == []
  end

  defp graph(nodes, edges) do
    graph = %Graph{id: "graph", nodes: [], adjacency_list: %{}}
    graph = Enum.reduce(nodes, graph, &Graph.add_node(&2, &1))
    Enum.reduce(edges, graph, &Graph.add_edge(&2, &1))
  end

  defp node(id, type, data) do
    %Node{id: id, graph_id: "graph", type: Atom.to_string(type), data: data, view_data: nil}
  end

  defp edge(id, from_id, to_id, type, data) do
    %Edge{
      id: id,
      graph_id: "graph",
      from_id: from_id,
      to_id: to_id,
      type: Atom.to_string(type),
      data: data
    }
  end

  defp service_data, do: %{"name" => "service", "protocol" => "tcp", "port" => 443}
  defp credential_data, do: %{"identifier" => "credential", "credential_type" => "password"}
end
