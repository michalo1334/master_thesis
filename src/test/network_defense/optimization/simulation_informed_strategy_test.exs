defmodule NetworkDefense.Optimization.SimulationInformedStrategyTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, NetworkSegment, Service, Vulnerability}
  alias NetworkDefense.Optimization.{SimulationInformedStrategy, SimulationObjective, Strategy}

  alias NetworkDefense.Relationships.{
    Contains,
    HasVulnerability,
    NetworkReachability,
    Runs,
    SegmentReachability
  }

  alias NetworkDefense.Rules.RemoteServiceExploitation

  test "chooses the patch with the largest simulated blast-radius reduction" do
    {graph, source} = graph()

    strategy = %SimulationInformedStrategy{
      initial_attacker_state: AttackerState.new(source.id),
      rules: [%RemoteServiceExploitation{}],
      run_count: 20,
      iteration_count: 10,
      seed: 42
    }

    assert [%PatchVulnerability{edge_id: "vulnerability-a"} | _] =
             Strategy.rank(strategy, [PatchVulnerability], graph, 1)
  end

  test "expected/2 simulates an unmaterialized canonical graph" do
    {graph, source} = graph()

    refute Enum.any?(Graph.edges(graph), &(&1.type == NetworkReachability))

    strategy = %SimulationInformedStrategy{
      initial_attacker_state: AttackerState.new(source.id),
      rules: [%RemoteServiceExploitation{}],
      run_count: 5,
      iteration_count: 5,
      seed: 42
    }

    {_mission_impact, blast_radius} = SimulationObjective.expected(graph, strategy)

    assert blast_radius > 1.0
  end

  test "excludes candidates without a strictly positive modeled reduction" do
    {graph, source} = mixed_reachability_graph()

    strategy = %SimulationInformedStrategy{
      initial_attacker_state: AttackerState.new(source.id),
      rules: [%RemoteServiceExploitation{}],
      run_count: 5,
      iteration_count: 5,
      seed: 42
    }

    assert [%PatchVulnerability{edge_id: "vulnerability-a"}] =
             Strategy.rank(strategy, [PatchVulnerability], graph, 2)
  end

  test "ranking_key orders conflicting outcomes per objective" do
    mission_heavy = {5.0, 1.0}
    blast_heavy = {1.0, 5.0}

    assert SimulationObjective.ranking_key(mission_heavy, :blast_radius_only, 0.0) <
             SimulationObjective.ranking_key(blast_heavy, :blast_radius_only, 0.0)

    assert SimulationObjective.ranking_key(blast_heavy, :mission_impact_only, 0.0) <
             SimulationObjective.ranking_key(mission_heavy, :mission_impact_only, 0.0)

    assert SimulationObjective.ranking_key(blast_heavy, :mission_then_blast_radius, 0.0) <
             SimulationObjective.ranking_key(mission_heavy, :mission_then_blast_radius, 0.0)
  end

  test "mission_impact_only ignores a candidate that only reduces blast radius" do
    {graph, source} = mixed_reachability_graph()

    strategy = %SimulationInformedStrategy{
      initial_attacker_state: AttackerState.new(source.id),
      rules: [%RemoteServiceExploitation{}],
      run_count: 5,
      iteration_count: 5,
      seed: 42,
      objective: :mission_impact_only
    }

    assert [] = Strategy.rank(strategy, [PatchVulnerability], graph, 2)
  end

  test "new/3 fills objective and feasibility from an optional model configuration" do
    {graph, source} = graph()

    params = %{
      simulation_params: %{
        monte_carlo_trials: 2,
        iterations_per_run: 2,
        initial_foothold_node_id: source.id,
        seed: 42,
        max_attempts: 1
      },
      model: %{objective: :blast_radius_only, require_pre_attack_feasibility: false}
    }

    assert {:ok, strategy} = SimulationInformedStrategy.new(graph, params)
    assert strategy.objective == :blast_radius_only
    assert strategy.require_pre_attack_feasibility == false
  end

  test "new/3 keeps standalone defaults without a model configuration" do
    {graph, source} = graph()

    params = %{
      simulation_params: %{
        monte_carlo_trials: 2,
        iterations_per_run: 2,
        initial_foothold_node_id: source.id,
        seed: 42,
        max_attempts: 1
      }
    }

    assert {:ok, strategy} = SimulationInformedStrategy.new(graph, params)
    assert strategy.objective == :mission_then_blast_radius
    assert strategy.require_pre_attack_feasibility == true
  end

  defp mixed_reachability_graph do
    source = GraphFixtures.node("source", Host, %{"name" => "internet"})
    host_a = GraphFixtures.node("host-a", Host, %{"name" => "a"})
    host_isolated = GraphFixtures.node("host-isolated", Host, %{"name" => "isolated"})
    source_segment = segment("source-segment")
    segment_a = segment("segment-a")
    isolated_segment = segment("isolated-segment")
    service_a = service("service-a")
    service_isolated = service("service-isolated")
    vulnerability_a = vulnerability("vulnerability-a")
    vulnerability_isolated = vulnerability("vulnerability-isolated")

    graph =
      GraphFixtures.graph(
        [
          source_segment,
          segment_a,
          isolated_segment,
          source,
          host_a,
          host_isolated,
          service_a,
          service_isolated,
          vulnerability_a,
          vulnerability_isolated
        ],
        [
          GraphFixtures.edge("contains-source", source_segment, source, Contains),
          GraphFixtures.edge("contains-a", segment_a, host_a, Contains),
          GraphFixtures.edge("contains-isolated", isolated_segment, host_isolated, Contains),
          GraphFixtures.edge(
            "policy-a",
            source_segment,
            segment_a,
            SegmentReachability,
            policy()
          ),
          GraphFixtures.edge("runs-a", host_a, service_a, Runs),
          GraphFixtures.edge("runs-isolated", host_isolated, service_isolated, Runs),
          GraphFixtures.edge(
            "vulnerability-a",
            service_a,
            vulnerability_a,
            HasVulnerability,
            privileges()
          ),
          GraphFixtures.edge(
            "vulnerability-isolated",
            service_isolated,
            vulnerability_isolated,
            HasVulnerability,
            privileges()
          )
        ]
      )

    {graph, source}
  end

  defp graph do
    source = GraphFixtures.node("source", Host, %{"name" => "internet"})
    host_a = GraphFixtures.node("host-a", Host, %{"name" => "a"})
    host_b = GraphFixtures.node("host-b", Host, %{"name" => "b"})
    host_c = GraphFixtures.node("host-c", Host, %{"name" => "c"})
    source_segment = segment("source-segment")
    segment_a = segment("segment-a")
    segment_b = segment("segment-b")
    segment_c = segment("segment-c")
    service_a = service("service-a")
    service_b = service("service-b")
    service_c = service("service-c")
    vulnerability_a = vulnerability("vulnerability-a")
    vulnerability_b = vulnerability("vulnerability-b")
    vulnerability_c = vulnerability("vulnerability-c")

    graph =
      GraphFixtures.graph(
        [
          source_segment,
          segment_a,
          segment_b,
          segment_c,
          source,
          host_a,
          host_b,
          host_c,
          service_a,
          service_b,
          service_c,
          vulnerability_a,
          vulnerability_b,
          vulnerability_c
        ],
        [
          GraphFixtures.edge("contains-source", source_segment, source, Contains),
          GraphFixtures.edge("contains-a", segment_a, host_a, Contains),
          GraphFixtures.edge("contains-b", segment_b, host_b, Contains),
          GraphFixtures.edge("contains-c", segment_c, host_c, Contains),
          GraphFixtures.edge(
            "policy-a",
            source_segment,
            segment_a,
            SegmentReachability,
            policy()
          ),
          GraphFixtures.edge("policy-b", segment_a, segment_b, SegmentReachability, policy()),
          GraphFixtures.edge(
            "policy-c",
            source_segment,
            segment_c,
            SegmentReachability,
            policy()
          ),
          GraphFixtures.edge("runs-a", host_a, service_a, Runs),
          GraphFixtures.edge("runs-b", host_b, service_b, Runs),
          GraphFixtures.edge("runs-c", host_c, service_c, Runs),
          GraphFixtures.edge(
            "vulnerability-a",
            service_a,
            vulnerability_a,
            HasVulnerability,
            privileges()
          ),
          GraphFixtures.edge(
            "vulnerability-b",
            service_b,
            vulnerability_b,
            HasVulnerability,
            privileges()
          ),
          GraphFixtures.edge(
            "vulnerability-c",
            service_c,
            vulnerability_c,
            HasVulnerability,
            privileges()
          )
        ]
      )

    {graph, source}
  end

  defp segment(id),
    do: GraphFixtures.node(id, NetworkSegment, %{"name" => id})

  defp policy, do: %{"protocol" => "tcp"}

  defp service(id),
    do: GraphFixtures.node(id, Service, %{"name" => id, "protocol" => "tcp", "port" => 443})

  defp vulnerability(id) do
    GraphFixtures.node(id, Vulnerability, %{
      "identifier" => id,
      "cvss" => cvss(),
      "exploit_probability" => 1.0
    })
  end

  defp privileges, do: %{"required_privilege" => "none", "granted_privilege" => "user"}

  defp cvss do
    %{
      "attack_vector" => "network",
      "attack_complexity" => "low",
      "privileges_required" => "none",
      "user_interaction" => "none",
      "scope" => "unchanged",
      "confidentiality_impact" => "high",
      "integrity_impact" => "none",
      "availability_impact" => "none"
    }
  end
end
