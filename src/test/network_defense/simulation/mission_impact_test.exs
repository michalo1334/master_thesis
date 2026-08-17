defmodule NetworkDefense.Simulation.MissionImpactTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, MissionCapability, NetworkSegment, Service}
  alias NetworkDefense.Relationships.{Contains, Runs, SegmentReachability, Supports}
  alias NetworkDefense.Simulation.MissionImpact

  test "marks a capability down when fewer than its required supports remain" do
    primary = GraphFixtures.node("primary", Host, %{"name" => "primary"})
    replica = GraphFixtures.node("replica", Host, %{"name" => "replica"})
    capability = capability("orders", 8.0, 2)

    graph =
      GraphFixtures.graph(
        [primary, replica, capability],
        [
          GraphFixtures.edge("supports-primary", primary, capability, Supports),
          GraphFixtures.edge("supports-replica", replica, capability, Supports)
        ]
      )

    assert MissionImpact.final(graph, []) == 0.0
    assert MissionImpact.final(graph, [primary.id]) == 8.0
  end

  test "models one remaining support as sufficient when k is one" do
    primary = GraphFixtures.node("primary", Host, %{"name" => "primary"})
    replica = GraphFixtures.node("replica", Host, %{"name" => "replica"})
    capability = capability("orders", 8.0, 1)

    graph =
      GraphFixtures.graph(
        [primary, replica, capability],
        [
          GraphFixtures.edge("supports-primary", primary, capability, Supports),
          GraphFixtures.edge("supports-replica", replica, capability, Supports)
        ]
      )

    assert MissionImpact.final(graph, [primary.id]) == 0.0
    assert MissionImpact.final(graph, [primary.id, replica.id]) == 8.0
  end

  test "keeps a capability operational pre-attack when all required flows exist" do
    graph = flow_graph()

    assert MissionImpact.pre_attack_feasible?(graph)

    assert [status] = MissionImpact.pre_attack_status(graph)
    assert status.down? == false
    assert status.required_flow_count == 1
    assert status.missing_flow_count == 0
    assert status.compromised_target_host_count == 0
  end

  test "marks a capability down when a required flow is not materialized" do
    graph = flow_graph(extra_flow: {"db-seg", "db"})

    refute MissionImpact.pre_attack_feasible?(graph)

    assert [status] = MissionImpact.pre_attack_status(graph)
    assert status.down? == true
    assert status.required_flow_count == 2
    assert status.missing_flow_count == 1
  end

  test "marks a capability down when the target service host is compromised" do
    graph = flow_graph()
    target_host = GraphFixtures.node("target-host", Host, %{"name" => "target-host"})

    assert MissionImpact.final(graph, [target_host.id]) == 8.0

    assert [status] = MissionImpact.capability_statuses(graph, [target_host.id])
    assert status.down? == true
    assert status.compromised_target_host_count == 1
    assert status.missing_flow_count == 0
  end

  defp capability(id, impact_weight, min_operational_support, required_flows \\ []) do
    GraphFixtures.node(id, MissionCapability, %{
      "name" => id,
      "impact_weight" => impact_weight,
      "min_operational_support" => min_operational_support,
      "required_flows" => required_flows
    })
  end

  defp flow_graph(opts \\ []) do
    source_segment = GraphFixtures.node("source-seg", NetworkSegment, %{"name" => "Source"})
    target_segment = GraphFixtures.node("target-seg", NetworkSegment, %{"name" => "Target"})
    source_host = GraphFixtures.node("source-host", Host, %{"name" => "source-host"})
    target_host = GraphFixtures.node("target-host", Host, %{"name" => "target-host"})

    api =
      GraphFixtures.node("api", Service, %{"name" => "api", "protocol" => "tcp", "port" => 8080})

    db_segment = GraphFixtures.node("db-seg", NetworkSegment, %{"name" => "DB"})
    db_host = GraphFixtures.node("db-host", Host, %{"name" => "db-host"})
    db = GraphFixtures.node("db", Service, %{"name" => "db", "protocol" => "tcp", "port" => 5432})

    required_flows = [%{"source_segment_id" => "source-seg", "target_service_id" => "api"}]

    required_flows =
      case Keyword.get(opts, :extra_flow) do
        {segment_id, service_id} ->
          required_flows ++
            [%{"source_segment_id" => segment_id, "target_service_id" => service_id}]

        nil ->
          required_flows
      end

    capability = capability("orders", 8.0, 1, required_flows)

    nodes = [
      source_segment,
      target_segment,
      source_host,
      target_host,
      api,
      db_segment,
      db_host,
      db,
      capability
    ]

    edges = [
      GraphFixtures.edge("source-contains", source_segment, source_host, Contains),
      GraphFixtures.edge("target-contains", target_segment, target_host, Contains),
      GraphFixtures.edge("db-contains", db_segment, db_host, Contains),
      GraphFixtures.edge("target-runs-api", target_host, api, Runs),
      GraphFixtures.edge("db-runs-db", db_host, db, Runs),
      GraphFixtures.edge("policy", source_segment, target_segment, SegmentReachability, %{
        "protocol" => "tcp"
      }),
      GraphFixtures.edge("supports-source", source_host, capability, Supports),
      GraphFixtures.edge("supports-target", target_host, capability, Supports)
    ]

    GraphFixtures.graph(nodes, edges)
  end
end
