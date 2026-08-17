defmodule NetworkDefense.Optimization.OptimizerFeasibilityTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.DefenseActions.BlockSegmentReachability
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, MissionCapability, NetworkSegment, Service}
  alias NetworkDefense.Optimization.{Optimizer, TopologySegmentationStrategy}
  alias NetworkDefense.Relationships.{Contains, Runs, SegmentReachability, Supports}

  test "refuses to cut a segment policy that a required flow depends on" do
    {graph, source} = required_flow_graph()

    result =
      Optimizer.apply(
        graph,
        %TopologySegmentationStrategy{initial_foothold_node_id: source.id},
        1
      )

    assert result.actions == []
    assert result.budget_used == 0
    assert Graph.edge(result.graph, "target-policy")
  end

  test "cuts a non-required policy while keeping the required flow intact" do
    {graph, source} = required_flow_graph(extra_policy: true)

    result =
      Optimizer.apply(
        graph,
        %TopologySegmentationStrategy{initial_foothold_node_id: source.id},
        1
      )

    assert [%BlockSegmentReachability{edge_id: "a-other-policy"}] = result.actions
    assert result.budget_used == 1
    assert Graph.edge(result.graph, "target-policy")
    refute Graph.edge(result.graph, "a-other-policy")
  end

  defp required_flow_graph(opts \\ []) do
    source_segment = segment("source-segment")
    target_segment = segment("target-segment")
    source = host("source")
    target = host("target")
    api = service("api")

    capability =
      GraphFixtures.node("orders", MissionCapability, %{
        "name" => "orders",
        "impact_weight" => 8.0,
        "min_operational_support" => 1,
        "required_flows" => [
          %{"source_segment_id" => "source-segment", "target_service_id" => "api"}
        ]
      })

    nodes = [source_segment, target_segment, source, target, api, capability]

    edges = [
      GraphFixtures.edge("contains-source", source_segment, source, Contains),
      GraphFixtures.edge("contains-target", target_segment, target, Contains),
      GraphFixtures.edge("runs-api", target, api, Runs),
      GraphFixtures.edge("target-policy", source_segment, target_segment, SegmentReachability, %{
        "protocol" => "tcp"
      }),
      GraphFixtures.edge("supports-source", source, capability, Supports),
      GraphFixtures.edge("supports-target", target, capability, Supports)
    ]

    {nodes, edges} =
      if Keyword.get(opts, :extra_policy) do
        other_segment = segment("other-segment")
        other = host("other")
        other_service = service("other-service")

        extra_edges = [
          GraphFixtures.edge("contains-other", other_segment, other, Contains),
          GraphFixtures.edge("runs-other", other, other_service, Runs),
          GraphFixtures.edge(
            "a-other-policy",
            source_segment,
            other_segment,
            SegmentReachability,
            %{"protocol" => "tcp"}
          )
        ]

        {nodes ++ [other_segment, other, other_service], edges ++ extra_edges}
      else
        {nodes, edges}
      end

    {GraphFixtures.graph(nodes, edges), source}
  end

  defp host(id), do: GraphFixtures.node(id, Host, %{"name" => id})

  defp segment(id), do: GraphFixtures.node(id, NetworkSegment, %{"name" => id})

  defp service(id),
    do: GraphFixtures.node(id, Service, %{"name" => id, "protocol" => "tcp", "port" => 443})
end
