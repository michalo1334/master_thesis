defmodule NetworkDefense.Graph.MaterializeReachabilityTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.{Edge, Graph}
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Nodes.{Host, NetworkSegment, Service}
  alias NetworkDefense.Relationships.{Contains, NetworkReachability, Runs, SegmentReachability}

  import NetworkDefense.GraphFixtures, only: [edge: 4, edge: 5, graph: 3, node: 4]

  describe "deny by default" do
    test "emits no operational flows without a matching policy" do
      segments = segments()
      graph = canonical(segments, [])

      assert materialize(graph) |> operational_edges() == []
    end

    test "keeps canonical nodes and edges unchanged" do
      segments = segments()

      graph =
        canonical(segments, [{segments.external, segments.internal, %{"protocol" => "tcp"}}])

      materialized = materialize(graph)

      assert Graph.nodes(materialized) == Graph.nodes(graph)

      assert Enum.map(canonical_edges(materialized), & &1.id) ==
               Enum.map(canonical_edges(graph), & &1.id)
    end
  end

  describe "directed matching" do
    test "emits flows only from the source segment to the target segment" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal, %{"protocol" => "tcp"}}
        ])

      flows = flow_pairs(materialize(graph))

      assert {"internet", "https"} in flows
      assert {"internet", "ssh"} in flows
      assert {"internet", "api"} in flows
      refute {"dmz-web-1", "https"} in flows
      refute {"internal-api-1", "api"} in flows
    end
  end

  describe "same-segment self rules" do
    test "requires an explicit self policy for same-segment traffic" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal, %{"protocol" => "tcp"}}
        ])

      flows = flow_pairs(materialize(graph))
      refute {"dmz-web-1", "https"} in flows
      refute {"internal-api-1", "api"} in flows

      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal, %{"protocol" => "tcp"}},
          {segments.internal, segments.internal, %{"protocol" => "tcp"}}
        ])

      flows = flow_pairs(materialize(graph))
      assert {"dmz-web-1", "https"} in flows
      assert {"internal-api-1", "api"} in flows
    end
  end

  describe "protocol matching" do
    test "any protocol reaches every service protocol" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal, %{"protocol" => "any"}}
        ])

      flows = flow_pairs(materialize(graph))
      assert {"internet", "https"} in flows
      assert {"internet", "dns"} in flows
    end

    test "an exact protocol reaches only services of that protocol" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal, %{"protocol" => "udp"}}
        ])

      assert [{"internet", "dns"}] == flow_pairs(materialize(graph))
    end
  end

  describe "port range matching" do
    test "an absent range matches every port" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal, %{"protocol" => "tcp"}}
        ])

      flows = flow_pairs(materialize(graph))
      assert {"internet", "https"} in flows
      assert {"internet", "ssh"} in flows
      assert {"internet", "api"} in flows
      refute {"internet", "dns"} in flows
    end

    test "an inclusive range matches only contained ports" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal,
           %{"protocol" => "tcp", "port_start" => 8080, "port_end" => 8080}}
        ])

      assert [{"internet", "api"}] == flow_pairs(materialize(graph))

      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal,
           %{"protocol" => "tcp", "port_start" => 20, "port_end" => 100}}
        ])

      assert [{"internet", "ssh"}] == flow_pairs(materialize(graph))
    end

    test "a range that misses all ports denies the flow" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal,
           %{"protocol" => "tcp", "port_start" => 1000, "port_end" => 2000}}
        ])

      assert [] == flow_pairs(materialize(graph))
    end
  end

  describe "deduplication" do
    test "deduplicates overlapping policies by source host and target service" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal, %{"protocol" => "any"}},
          {segments.external, segments.internal,
           %{"protocol" => "tcp", "port_start" => 22, "port_end" => 443}}
        ])

      edges = operational_edges(materialize(graph))

      assert Enum.map(edges, &{&1.from_id, &1.to_id}) ==
               Enum.sort([
                 {"internet", "https"},
                 {"internet", "ssh"},
                 {"internet", "api"},
                 {"internet", "dns"}
               ])
    end
  end

  describe "deterministic ids and ordering" do
    test "produces stable sorted UUID ids derived from graph and endpoint ids" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal, %{"protocol" => "any"}}
        ])

      first = operational_edges(materialize(graph))
      second = operational_edges(materialize(graph))

      assert Enum.map(first, & &1.id) == Enum.map(second, & &1.id)

      assert Enum.map(first, &{&1.from_id, &1.to_id}) ==
               Enum.sort(Enum.map(first, &{&1.from_id, &1.to_id}))

      for edge <- first do
        id = edge.id
        assert {:ok, ^id} = Ecto.UUID.cast(id)
      end
    end

    test "ids change with the graph id but keep the same endpoint pairs" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal, %{"protocol" => "any"}}
        ])

      other_segments = segments("other-graph")

      other =
        canonical(
          other_segments,
          [
            {other_segments.external, other_segments.internal, %{"protocol" => "any"}}
          ],
          "other-graph"
        )

      edges = operational_edges(materialize(graph))
      other_edges = operational_edges(materialize(other))

      assert Enum.map(edges, &{&1.from_id, &1.to_id}) ==
               Enum.map(other_edges, &{&1.from_id, &1.to_id})

      assert Enum.map(edges, & &1.id) != Enum.map(other_edges, & &1.id)
    end
  end

  describe "idempotence" do
    test "repeated materialization returns the same graph" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal, %{"protocol" => "any"}}
        ])

      materialized = materialize(graph)
      assert materialize(materialized) == materialized
    end

    test "strips pre-existing marker edges and regenerates deterministic ones" do
      segments = segments()

      graph =
        canonical(segments, [
          {segments.external, segments.internal, %{"protocol" => "any"}}
        ])

      random_id = Ecto.UUID.generate()
      internet = Graph.node(graph, "internet")
      https = Graph.node(graph, "https")

      graph =
        Graph.add_edge(graph, %Edge{
          id: random_id,
          graph_id: graph.id,
          from_id: internet.id,
          to_id: https.id,
          type: NetworkReachability,
          data: %NetworkReachability{}
        })

      materialized = materialize(graph)

      refute Enum.any?(Graph.edges(materialized), &(&1.id == random_id))

      assert Enum.map(operational_edges(materialized), & &1.id) ==
               Enum.map(operational_edges(materialize(graph)), & &1.id)
    end
  end

  defp materialize(graph), do: MaterializeReachability.materialize(graph)

  defp segments(graph_id \\ "graph") do
    %{
      external: node("ext-seg", NetworkSegment, %{"name" => "External"}, graph_id),
      internal: node("int-seg", NetworkSegment, %{"name" => "Internal"}, graph_id)
    }
  end

  defp canonical(%{external: external, internal: internal}, policies, graph_id \\ "graph") do
    internet = node("internet", Host, %{"name" => "internet"}, graph_id)
    dmz = node("dmz-web-1", Host, %{"name" => "dmz-web-1"}, graph_id)
    api_host = node("internal-api-1", Host, %{"name" => "internal-api-1"}, graph_id)

    https =
      node("https", Service, %{"name" => "https", "protocol" => "tcp", "port" => 443}, graph_id)

    ssh =
      node("ssh", Service, %{"name" => "ssh", "protocol" => "tcp", "port" => 22}, graph_id)

    api = node("api", Service, %{"name" => "api", "protocol" => "tcp", "port" => 8080}, graph_id)
    dns = node("dns", Service, %{"name" => "dns", "protocol" => "udp", "port" => 53}, graph_id)

    nodes = [external, internal, internet, dmz, api_host, https, ssh, api, dns]

    edges = [
      edge("ext-internet", external, internet, Contains),
      edge("int-dmz", internal, dmz, Contains),
      edge("int-api", internal, api_host, Contains),
      edge("dmz-https", dmz, https, Runs),
      edge("dmz-ssh", dmz, ssh, Runs),
      edge("api-api", api_host, api, Runs),
      edge("api-dns", api_host, dns, Runs)
    ]

    policy_edges =
      policies
      |> Enum.with_index()
      |> Enum.map(fn {{from, to, data}, index} ->
        edge("policy-#{index}", from, to, SegmentReachability, data)
      end)

    graph(nodes, edges ++ policy_edges, graph_id)
  end

  defp operational_edges(graph) do
    graph
    |> Graph.edges()
    |> Enum.filter(&(&1.type == NetworkReachability))
    |> Enum.sort_by(&{&1.from_id, &1.to_id, &1.id})
  end

  defp canonical_edges(graph) do
    graph
    |> Graph.edges()
    |> Enum.reject(&(&1.type == NetworkReachability))
    |> Enum.sort_by(& &1.id)
  end

  defp flow_pairs(graph) do
    Enum.map(operational_edges(graph), fn edge ->
      {Graph.node(graph, edge.from_id).data.name, Graph.node(graph, edge.to_id).data.name}
    end)
  end
end
