defmodule NetworkDefense.Graph.GraphDiffTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.{Graph, GraphDiff, Node}
  alias NetworkDefense.Nodes.{Host, NetworkSegment}
  alias NetworkDefense.Relationships.Contains

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

  defp node(graph, type, data) do
    Node.new(graph.id, %{
      type: Atom.to_string(type),
      data: data,
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    })
  end

  defp contains(graph, segment, host),
    do: Graph.add_edge(graph, segment, host, %{type: Atom.to_string(Contains), data: %{}})

  defp edge(graph, segment, host),
    do:
      NetworkDefense.Graph.Edge.new(graph.id, segment.id, host.id, %{
        type: Atom.to_string(Contains),
        data: %{}
      })
end
