defmodule NetworkDefense.Optimization.OptimizationReportTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.NetworkSegment
  alias NetworkDefense.Optimization.{OptimizationAction, OptimizationReport, OptimizationRun}
  alias NetworkDefense.Relationships.SegmentReachability

  test "summarizes a segment-boundary cut with source, target, protocol, and port range" do
    source = segment("source-segment")
    target = segment("target-segment")

    graph =
      GraphFixtures.graph(
        [source, target],
        [
          GraphFixtures.edge(
            "policy-1",
            source,
            target,
            SegmentReachability,
            %{"protocol" => "tcp", "port_start" => 443, "port_end" => 443}
          )
        ]
      )

    report = report(graph, [block_action("policy-1")])

    assert [
             %{
               id: "policy-1",
               label: "Cut source-segment to target-segment (tcp:443-443)",
               kind: "Segment-boundary cut",
               cost: 1
             }
           ] = report.actions
  end

  test "renders a policy without a port range as protocol only" do
    source = segment("source-segment")
    target = segment("target-segment")

    graph =
      GraphFixtures.graph(
        [source, target],
        [
          GraphFixtures.edge(
            "policy-2",
            source,
            target,
            SegmentReachability,
            %{"protocol" => "udp"}
          )
        ]
      )

    report = report(graph, [block_action("policy-2")])

    assert [
             %{label: "Cut source-segment to target-segment (udp)", kind: "Segment-boundary cut"}
           ] = report.actions
  end

  test "emits assembly progress through the callback" do
    source = segment("source-segment")
    target = segment("target-segment")

    graph =
      GraphFixtures.graph(
        [source, target],
        [
          GraphFixtures.edge(
            "policy-1",
            source,
            target,
            SegmentReachability,
            %{"protocol" => "tcp", "port_start" => 443, "port_end" => 443}
          )
        ]
      )

    report =
      OptimizationReport.generate(
        %OptimizationRun{
          id: "run-1",
          graph_revision_id: "revision-1",
          strategy: "topology_segmentation",
          requested_budget: 1,
          used_budget: 1,
          runtime_ms: 1,
          actions: [block_action("policy-1")]
        },
        graph,
        fn graph_id, graph_revision_id, completed, total, detail ->
          send(self(), {graph_id, graph_revision_id, completed, total, detail})
          :ok
        end
      )

    assert %OptimizationReport{} = report

    received = for _ <- 1..2, do: receive(do: (msg -> msg))

    assert Enum.any?(received, fn {graph_id, graph_revision_id, c, t, d} ->
             graph_id == graph.id and graph_revision_id == graph.revision_id and
               {c, t, d} == {1, 2, "Loading optimization run"}
           end)

    assert Enum.any?(received, fn {_, _, c, t, d} ->
             {c, t, d} == {2, 2, "Building action summaries"}
           end)
  end

  defp report(graph, actions) do
    OptimizationReport.generate(
      %OptimizationRun{
        id: "run-1",
        graph_revision_id: "revision-1",
        strategy: "topology_segmentation",
        requested_budget: 1,
        used_budget: 1,
        runtime_ms: 1,
        actions: actions
      },
      graph
    )
  end

  defp block_action(target_id) do
    %OptimizationAction{
      action_type: "BlockSegmentReachability",
      target_id: target_id,
      cost: 1,
      position: 1
    }
  end

  defp segment(id), do: GraphFixtures.node(id, NetworkSegment, %{"name" => id})
end
