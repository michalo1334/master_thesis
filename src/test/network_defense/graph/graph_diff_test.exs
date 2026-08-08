defmodule NetworkDefense.Graph.GraphDiffTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.{Edge, Graph, GraphDiff, Node}
  alias NetworkDefense.Nodes.{Host, NetworkSegment, Service}
  alias NetworkDefense.Relationships.{Contains, NetworkReachability, Runs, SegmentReachability}

  test "compares a host moved between segments" do
    base = Graph.new("Topology")
    host = node(base, Host, %{"name" => "host"})
    dmz = node(base, NetworkSegment, %{"name" => "DMZ"})
    base = base |> Graph.add_node(host) |> Graph.add_node(dmz) |> contains(dmz, host)

    internal = node(base, NetworkSegment, %{"name" => "Internal"})
    candidate_host = %{host | id: host.id}

    {:ok, candidate} =
      Graph.hydrate(
        %{base | nodes: [], edges: [], adjacency_list: %{}},
        [candidate_host, internal],
        [edge(base, internal, candidate_host)]
      )

    assert %{graph: graph} = GraphDiff.structural(base, candidate)
    assert [_, _] = Graph.edges(graph)
  end

  test "a removed SegmentReachability yields one removed policy edge and no operational edge" do
    {base, policy_id} = canonical_graph()
    candidate = Graph.remove_edge_by_id(base, policy_id)

    assert %{graph: graph, edge_status: edge_status, edge_counts: edge_counts} =
             GraphDiff.structural(base, candidate)

    assert edge_counts == %{added: 0, removed: 1, unchanged: 4}
    assert Enum.any?(edge_status, &(&1.id == policy_id and &1.status == "removed"))
    refute Enum.any?(edge_status, &(&1.status == "added"))
    refute Enum.any?(Graph.edges(graph), &(&1.type == NetworkReachability))
  end

  test "a SegmentReachability data change yields one removed and one added policy edge" do
    {base, policy_id} = canonical_graph()

    [dmz_id, internal_id] =
      base |> Graph.nodes() |> Enum.filter(&(&1.type == NetworkSegment)) |> Enum.map(& &1.id)

    changed_policy_id = Ecto.UUID.generate()

    candidate =
      base
      |> Graph.remove_edge_by_id(policy_id)
      |> Graph.add_edge(%{
        Edge.new(base.id, dmz_id, internal_id, %{
          type: Atom.to_string(SegmentReachability),
          data: %{"protocol" => "udp", "port_start" => 53, "port_end" => 53}
        })
        | id: changed_policy_id
      })

    assert %{graph: graph, edge_status: edge_status, edge_counts: edge_counts} =
             GraphDiff.structural(base, candidate)

    assert edge_counts == %{added: 1, removed: 1, unchanged: 4}
    assert Enum.count(edge_status, &(&1.status == "removed")) == 1
    assert Enum.count(edge_status, &(&1.status == "added")) == 1
    assert Enum.any?(edge_status, &(&1.id == policy_id and &1.status == "removed"))
    assert Enum.any?(edge_status, &(&1.id == changed_policy_id and &1.status == "added"))
    refute Enum.any?(Graph.edges(graph), &(&1.type == NetworkReachability))
  end

  defp canonical_graph do
    base = Graph.new("Topology")

    dmz = node(base, NetworkSegment, %{"name" => "DMZ"})
    internal = node(base, NetworkSegment, %{"name" => "Internal"})
    host_a = node(base, Host, %{"name" => "host-a"})
    host_b = node(base, Host, %{"name" => "host-b"})
    service_a = node(base, Service, %{"name" => "web", "protocol" => "tcp", "port" => 443})
    service_b = node(base, Service, %{"name" => "db", "protocol" => "tcp", "port" => 5432})
    policy_id = Ecto.UUID.generate()

    base =
      base
      |> Graph.add_node(dmz)
      |> Graph.add_node(internal)
      |> Graph.add_node(host_a)
      |> Graph.add_node(host_b)
      |> Graph.add_node(service_a)
      |> Graph.add_node(service_b)
      |> contains(dmz, host_a)
      |> contains(internal, host_b)
      |> runs(host_a, service_a)
      |> runs(host_b, service_b)
      |> Graph.add_edge(%{
        Edge.new(base.id, dmz.id, internal.id, %{
          type: Atom.to_string(SegmentReachability),
          data: %{"protocol" => "tcp", "port_start" => 443, "port_end" => 443}
        })
        | id: policy_id
      })

    {base, policy_id}
  end

  defp node(graph, type, data) do
    Node.new(graph.id, %{
      type: Atom.to_string(type),
      data: data,
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    })
  end

  defp contains(graph, segment, host),
    do: Graph.add_edge(graph, segment, host, %{type: Atom.to_string(Contains), data: %{}})

  defp runs(graph, host, service),
    do: Graph.add_edge(graph, host, service, %{type: Atom.to_string(Runs), data: %{}})

  defp edge(graph, segment, host),
    do:
      Edge.new(graph.id, segment.id, host.id, %{
        type: Atom.to_string(Contains),
        data: %{}
      })
end
