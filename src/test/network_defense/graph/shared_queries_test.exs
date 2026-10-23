defmodule NetworkDefense.Graph.SharedQueriesTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Nodes.{Host, NetworkSegment}
  alias NetworkDefense.Relationships.Contains

  import NetworkDefense.GraphFixtures, only: [edge: 4, graph: 2, node: 3]

  test "GRAPH-QUERY-01: groups contained hosts by segment and ignores other edges" do
    first_segment = node("segment-1", NetworkSegment, %{"name" => "First"})
    second_segment = node("segment-2", NetworkSegment, %{"name" => "Second"})
    first_host = node("host-1", Host, %{"name" => "First"})
    second_host = node("host-2", Host, %{"name" => "Second"})

    graph =
      graph(
        [first_segment, second_segment, first_host, second_host],
        [
          edge("contains-1", first_segment, first_host, Contains),
          edge("contains-2", first_segment, second_host, Contains)
        ]
      )

    assert Graph.hosts_by_segment(graph) == %{
             "segment-1" => ["host-1", "host-2"]
           }
  end
end
