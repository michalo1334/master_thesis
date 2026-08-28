defmodule NetworkDefense.Simulation.SimulationReportTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Actions.AttemptedAction
  alias NetworkDefense.Actions.ExploitVulnerability
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Nodes.{Host, MissionCapability, NetworkSegment, Service}

  alias NetworkDefense.Relationships.{
    Contains,
    NetworkReachability,
    Runs,
    SegmentReachability,
    Supports
  }

  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.SimulationReport
  alias NetworkDefense.Simulation.Run
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchSimulationReportReply

  import NetworkDefense.GraphFixtures

  test "generates grouped raw report data for completed simulations" do
    report = SimulationReport.generate(experiment([run("source-host")]))

    assert %{expected_blast_radius: 1.0, median_blast_radius: 1, host_count: 3} = report.summary

    assert %SimulationReport.Charts{
             histogram: [%{lower_bound: 1, upper_bound: 1, count: 1}],
             cdf: [%{compromised_hosts: 1, cumulative_probability: 1.0}],
             convergence: [%{run: 1, mean_blast_radius: 1.0}],
             action_success: []
           } = report.charts
  end

  test "counts hosts without structural graph nodes" do
    graph = %Graph{
      id: "graph",
      revision_id: "revision",
      title: "Test graph",
      nodes: [
        %{id: "host", type: Host},
        %{id: "segment", type: NetworkSegment},
        %{id: "service", type: Service}
      ]
    }

    assert %{summary: %{host_count: 1}} =
             [run("source-host")]
             |> experiment(graph)
             |> SimulationReport.generate()
  end

  test "returns empty series when no simulations were persisted" do
    report = SimulationReport.generate(experiment([]))

    assert %SimulationReport.Charts{
             cdf: [],
             convergence: [],
             action_success: []
           } = report.charts
  end

  test "emits assembly progress through the callback" do
    report =
      experiment([])
      |> SimulationReport.generate(fn graph_id, graph_revision_id, completed, total, detail ->
        send(self(), {graph_id, graph_revision_id, completed, total, detail})
        :ok
      end)

    assert %SimulationReport{} = report

    received = for _ <- 1..6, do: receive(do: (msg -> msg))

    assert Enum.any?(received, fn {graph_id, graph_revision_id, c, t, d} ->
             graph_id == "graph" and graph_revision_id == "revision" and
               {c, t, d} == {1, 6, "Loading experiment data"}
           end)

    assert Enum.any?(received, fn {_, _, c, t, d} ->
             {c, t, d} == {2, 6, "Computing blast radius statistics"}
           end)

    assert Enum.any?(received, fn {_, _, c, t, d} ->
             {c, t, d} == {3, 6, "Computing mission impact statistics"}
           end)

    assert Enum.any?(received, fn {_, _, c, t, d} ->
             {c, t, d} == {4, 6, "Materializing operational flows"}
           end)

    assert Enum.any?(received, fn {_, _, c, t, d} ->
             {c, t, d} == {5, 6, "Aggregating action results"}
           end)

    assert Enum.any?(received, fn {_, _, c, t, d} ->
             {c, t, d} == {6, 6, "Computing compromise probabilities"}
           end)
  end

  test "maps a typed report to the web contract" do
    graph = %{Graph.new("Test graph") | revision_id: Ecto.UUID.generate()}

    assert {:ok,
            %FetchSimulationReportReply{
              summary: %{expected_blast_radius: 1.0},
              charts: %{convergence: [%{run: 1, mean_blast_radius: 1.0}]},
              operational_flows: []
            }} =
             experiment([run("source-host")], graph)
             |> SimulationReport.generate()
             |> FetchSimulationReportReply.from_domain()
  end

  test "reports and serializes final mission impact and capability disruption probabilities" do
    graph = Graph.new("Test graph")
    primary = node(Ecto.UUID.generate(), Host, %{"name" => "primary"}, graph.id)
    replica = node(Ecto.UUID.generate(), Host, %{"name" => "replica"}, graph.id)

    redundant =
      node(
        Ecto.UUID.generate(),
        MissionCapability,
        %{"name" => "Orders", "impact_weight" => 2.0, "min_operational_support" => 2},
        graph.id
      )

    single =
      node(
        Ecto.UUID.generate(),
        MissionCapability,
        %{"name" => "Billing", "impact_weight" => 5.0, "min_operational_support" => 1},
        graph.id
      )

    graph =
      graph(
        [primary, replica, redundant, single],
        [
          edge(Ecto.UUID.generate(), primary, redundant, Supports),
          edge(Ecto.UUID.generate(), replica, redundant, Supports),
          edge(Ecto.UUID.generate(), primary, single, Supports)
        ],
        graph.id
      )
      |> Map.put(:title, "Test graph")
      |> Map.put(:revision_id, Ecto.UUID.generate())

    report =
      [run(primary.id), run(replica.id)]
      |> experiment(graph)
      |> SimulationReport.generate()

    assert %{expected_mission_impact: 4.5, min_mission_impact: 2.0, max_mission_impact: 7.0} =
             report.summary

    assert report.charts.capability_impact == [
             %{capability_id: redundant.id, down_probability: 1.0},
             %{capability_id: single.id, down_probability: 0.5}
           ]

    assert {:ok, reply} = FetchSimulationReportReply.from_domain(report)

    assert %{summary: %{expected_mission_impact: 4.5}, charts: %{capability_impact: impacts}} =
             FetchSimulationReportReply.to_wire(reply)

    assert impacts == [
             %{capability_id: redundant.id, down_probability: 1.0},
             %{capability_id: single.id, down_probability: 0.5}
           ]
  end

  test "reports derived operational flows and their successful traversal by run" do
    {graph, source_host_id} = canonical_policy_graph()
    flow = operational_flow(graph)

    report =
      [run(source_host_id, [flow.id]), run(source_host_id)]
      |> experiment(graph)
      |> SimulationReport.generate()

    assert report.graph == graph
    refute Enum.any?(Graph.edges(report.graph), &(&1.type == NetworkReachability))

    assert report.operational_flows == [
             %{id: flow.id, from_id: flow.from_id, to_id: flow.to_id}
           ]

    assert report.charts.host_compromise == [
             %{host_id: source_host_id, compromise_probability: 1.0},
             %{host_id: "target-host", compromise_probability: 0.0}
           ]

    assert Enum.find(report.charts.edge_traversal, &(&1.edge_id == flow.id)) ==
             %{edge_id: flow.id, traversal_probability: 0.5}
  end

  test "serializes operational flows separately from the canonical report graph" do
    {graph, source_host_id} =
      canonical_policy_graph(Ecto.UUID.generate(), fn _ -> Ecto.UUID.generate() end)

    graph = %{graph | revision_id: Ecto.UUID.generate(), title: "Test graph"}
    flow = operational_flow(graph)

    report =
      [run(source_host_id, [flow.id])]
      |> experiment(graph)
      |> SimulationReport.generate()

    assert {:ok, reply} = FetchSimulationReportReply.from_domain(report)

    assert %{
             operational_flows: [
               %{id: flow_id, from_id: from_id, to_id: to_id}
             ],
             graph: %{edges: edges}
           } = FetchSimulationReportReply.to_wire(reply)

    assert {flow_id, from_id, to_id} == {flow.id, flow.from_id, flow.to_id}
    refute Enum.any?(edges, &(&1.type == "NetworkReachability"))
  end

  test "reports and serializes pre-attack capability status and feasibility" do
    graph = Graph.new("Test graph")
    source_segment = node(Ecto.UUID.generate(), NetworkSegment, %{"name" => "Source"}, graph.id)
    target_segment = node(Ecto.UUID.generate(), NetworkSegment, %{"name" => "Target"}, graph.id)
    source_host = node(Ecto.UUID.generate(), Host, %{"name" => "source"}, graph.id)
    target_host = node(Ecto.UUID.generate(), Host, %{"name" => "target"}, graph.id)

    service =
      node(
        Ecto.UUID.generate(),
        Service,
        %{"name" => "api", "port" => 8080, "protocol" => "tcp"},
        graph.id
      )

    capability =
      node(
        Ecto.UUID.generate(),
        MissionCapability,
        %{
          "name" => "Orders",
          "impact_weight" => 8.0,
          "min_operational_support" => 1,
          "required_flows" => [
            %{"source_segment_id" => source_segment.id, "target_service_id" => service.id}
          ]
        },
        graph.id
      )

    graph =
      graph(
        [source_segment, target_segment, source_host, target_host, service, capability],
        [
          edge(Ecto.UUID.generate(), source_segment, source_host, Contains),
          edge(Ecto.UUID.generate(), target_segment, target_host, Contains),
          edge(Ecto.UUID.generate(), target_host, service, Runs),
          edge(Ecto.UUID.generate(), source_host, capability, Supports),
          edge(
            Ecto.UUID.generate(),
            source_segment,
            target_segment,
            SegmentReachability,
            %{"protocol" => "tcp"}
          )
        ],
        graph.id
      )
      |> Map.put(:title, "Test graph")
      |> Map.put(:revision_id, Ecto.UUID.generate())

    report =
      [run(source_host.id)]
      |> experiment(graph)
      |> SimulationReport.generate()

    assert report.pre_attack_feasible

    assert [
             %{
               capability_id: capability_id,
               down?: false,
               required_flow_count: 1,
               missing_flow_count: 0,
               supporting_host_count: 1,
               min_operational_support: 1
             }
           ] = report.pre_attack_capability_statuses

    assert capability_id == capability.id

    assert {:ok, reply} = FetchSimulationReportReply.from_domain(report)

    assert %{
             feasible: true,
             capability_statuses: [
               %{
                 capability_id: ^capability_id,
                 operational: true,
                 required_flow_count: 1,
                 missing_flow_count: 0,
                 supporting_host_count: 1,
                 min_operational_support: 1
               }
             ]
           } = FetchSimulationReportReply.to_wire(reply)
  end

  test "reports an infeasible pre-attack scenario with a down capability" do
    graph = Graph.new("Test graph")
    source_segment = node(Ecto.UUID.generate(), NetworkSegment, %{"name" => "Source"}, graph.id)
    target_segment = node(Ecto.UUID.generate(), NetworkSegment, %{"name" => "Target"}, graph.id)
    source_host = node(Ecto.UUID.generate(), Host, %{"name" => "source"}, graph.id)
    target_host = node(Ecto.UUID.generate(), Host, %{"name" => "target"}, graph.id)

    service =
      node(
        Ecto.UUID.generate(),
        Service,
        %{"name" => "api", "port" => 8080, "protocol" => "tcp"},
        graph.id
      )

    db_segment = node(Ecto.UUID.generate(), NetworkSegment, %{"name" => "DB"}, graph.id)
    db_host = node(Ecto.UUID.generate(), Host, %{"name" => "db"}, graph.id)

    db =
      node(
        Ecto.UUID.generate(),
        Service,
        %{"name" => "db", "port" => 5432, "protocol" => "tcp"},
        graph.id
      )

    capability =
      node(
        Ecto.UUID.generate(),
        MissionCapability,
        %{
          "name" => "Orders",
          "impact_weight" => 8.0,
          "min_operational_support" => 1,
          "required_flows" => [
            %{"source_segment_id" => source_segment.id, "target_service_id" => service.id},
            %{"source_segment_id" => db_segment.id, "target_service_id" => db.id}
          ]
        },
        graph.id
      )

    graph =
      graph(
        [
          source_segment,
          target_segment,
          source_host,
          target_host,
          service,
          db_segment,
          db_host,
          db,
          capability
        ],
        [
          edge(Ecto.UUID.generate(), source_segment, source_host, Contains),
          edge(Ecto.UUID.generate(), target_segment, target_host, Contains),
          edge(Ecto.UUID.generate(), db_segment, db_host, Contains),
          edge(Ecto.UUID.generate(), target_host, service, Runs),
          edge(Ecto.UUID.generate(), db_host, db, Runs),
          edge(Ecto.UUID.generate(), source_host, capability, Supports),
          edge(
            Ecto.UUID.generate(),
            source_segment,
            target_segment,
            SegmentReachability,
            %{"protocol" => "tcp"}
          )
        ],
        graph.id
      )
      |> Map.put(:title, "Test graph")
      |> Map.put(:revision_id, Ecto.UUID.generate())

    report =
      [run(source_host.id)]
      |> experiment(graph)
      |> SimulationReport.generate()

    refute report.pre_attack_feasible

    assert [
             %{
               down?: true,
               missing_flow_count: 1,
               required_flow_count: 2,
               supporting_host_count: 1,
               min_operational_support: 1
             }
           ] = report.pre_attack_capability_statuses

    assert {:ok, reply} = FetchSimulationReportReply.from_domain(report)

    assert %{
             feasible: false,
             capability_statuses: [
               %{
                 operational: false,
                 missing_flow_count: 1,
                 required_flow_count: 2,
                 supporting_host_count: 1,
                 min_operational_support: 1
               }
             ]
           } = FetchSimulationReportReply.to_wire(reply)
  end

  defp experiment(
         runs,
         graph \\ %Graph{
           id: "graph",
           revision_id: "revision",
           title: "Test graph",
           nodes: [
             %{id: "host-1", type: Host},
             %{id: "host-2", type: Host},
             %{id: "host-3", type: Host}
           ]
         }
       ) do
    %Experiment{
      id: "experiment",
      graph_revision_id: graph.revision_id,
      graph: graph,
      iteration_count: 1,
      runs: runs
    }
  end

  defp run(foothold, supporting_edge_ids \\ nil) do
    state = AttackerState.new(foothold)

    Run.new(
      seed: 0,
      initial_attacker_state: state,
      iterations:
        if supporting_edge_ids do
          action = %ExploitVulnerability{
            source_host_id: foothold,
            supporting_edge_ids: supporting_edge_ids
          }

          [
            IterationStep.new(
              index: 1,
              success?: true,
              attempted_action: AttemptedAction.new(action),
              attacker_state: state
            )
          ]
        else
          []
        end
    )
  end

  defp canonical_policy_graph(graph_id \\ "graph", id_for \\ fn id -> id end) do
    source_segment =
      node(id_for.("source-segment"), NetworkSegment, %{"name" => "Source"}, graph_id)

    target_segment =
      node(id_for.("target-segment"), NetworkSegment, %{"name" => "Target"}, graph_id)

    source_host = node(id_for.("source-host"), Host, %{"name" => "source"}, graph_id)
    target_host = node(id_for.("target-host"), Host, %{"name" => "target"}, graph_id)

    service =
      node(
        id_for.("service"),
        Service,
        %{"name" => "ssh", "port" => 22, "protocol" => "tcp"},
        graph_id
      )

    graph =
      graph(
        [source_segment, target_segment, source_host, target_host, service],
        [
          edge(id_for.("source-contains"), source_segment, source_host, Contains),
          edge(id_for.("target-contains"), target_segment, target_host, Contains),
          edge(id_for.("target-runs"), target_host, service, Runs),
          edge(
            id_for.("policy"),
            source_segment,
            target_segment,
            SegmentReachability,
            %{"protocol" => "tcp"}
          )
        ],
        graph_id
      )

    {graph, source_host.id}
  end

  defp operational_flow(graph) do
    graph
    |> MaterializeReachability.materialize()
    |> Graph.edges()
    |> Enum.find(&(&1.type == NetworkReachability))
  end
end
