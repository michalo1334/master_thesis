defmodule NetworkDefense.Optimization.RandomStrategyTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.DefenseActions.{BlockSegmentReachability, RevokeCredential}
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Credential, Host, NetworkSegment, Service}
  alias NetworkDefense.Optimization.{RandomStrategy, Strategy}
  alias NetworkDefense.Relationships.{Contains, Runs, SegmentReachability}

  test "selects a concrete action for an eligible policy edge" do
    graph = policy_graph()

    assert [%BlockSegmentReachability{edge_id: "policy-ab"}] =
             Strategy.rank(%RandomStrategy{}, [BlockSegmentReachability], graph, 1)
  end

  test "selects a credential node for revocation" do
    graph = graph([node("credential", Credential, credential_data())], [])

    assert [%RevokeCredential{credential_id: "credential"}] =
             Strategy.rank(%RandomStrategy{}, [RevokeCredential], graph, 1)
  end

  test "returns no action when no eligible target exists" do
    graph = graph([node("host", Host, %{"name" => "host"})], [])

    assert Strategy.rank(%RandomStrategy{}, [BlockSegmentReachability], graph, 1) == []
  end

  test "returns no action when no action type is provided" do
    assert Strategy.rank(%RandomStrategy{}, [], graph([], []), 1) == []
  end

  test "uses the selection seed without changing process-global random state" do
    graph =
      graph(
        [
          node("credential-a", Credential, credential_data()),
          node("credential-b", Credential, credential_data())
        ],
        []
      )

    strategy = %RandomStrategy{seed: 1234}

    assert Strategy.rank(strategy, [RevokeCredential], graph, 1) ==
             Strategy.rank(strategy, [RevokeCredential], graph, 1)
  end

  defp policy_graph do
    segment_a = node("segment-a", NetworkSegment, %{"name" => "segment-a"})
    segment_b = node("segment-b", NetworkSegment, %{"name" => "segment-b"})
    host_a = node("host-a", Host, %{"name" => "host-a"})
    host_b = node("host-b", Host, %{"name" => "host-b"})
    service = node("service", Service, service_data())

    graph(
      [segment_a, segment_b, host_a, host_b, service],
      [
        edge("contains-a", segment_a, host_a, Contains, %{}),
        edge("contains-b", segment_b, host_b, Contains, %{}),
        edge("runs-b", host_b, service, Runs, %{}),
        edge("policy-ab", segment_a, segment_b, SegmentReachability, %{"protocol" => "tcp"})
      ]
    )
  end

  defp graph(nodes, edges) do
    graph = %Graph{id: "graph", nodes: [], adjacency_list: %{}}
    graph = Enum.reduce(nodes, graph, &Graph.add_node(&2, &1))
    Enum.reduce(edges, graph, &Graph.add_edge(&2, &1))
  end

  defp node(id, type, data) do
    GraphFixtures.node(id, type, data)
  end

  defp edge(id, from, to, type, data) do
    GraphFixtures.edge(id, from, to, type, data)
  end

  defp service_data, do: %{"name" => "service", "protocol" => "tcp", "port" => 443}
  defp credential_data, do: %{"identifier" => "credential", "credential_type" => "password"}
end
