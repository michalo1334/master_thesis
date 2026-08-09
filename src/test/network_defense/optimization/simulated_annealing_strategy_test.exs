defmodule NetworkDefense.Optimization.SimulatedAnnealingStrategyTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.AttackerState.AttackerState

  alias NetworkDefense.DefenseActions.{
    BlockSegmentReachability,
    PatchVulnerability,
    RevokeCredential
  }

  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, NetworkSegment, Service, Vulnerability}
  alias NetworkDefense.Optimization.{Optimizer, SimulatedAnnealingStrategy, Strategy}
  alias NetworkDefense.Relationships.{Contains, HasVulnerability, Runs, SegmentReachability}
  alias NetworkDefense.Rules.RemoteServiceExploitation

  test "returns a deterministic valid defense plan" do
    {graph, source} = graph()

    strategy = %SimulatedAnnealingStrategy{
      initial_attacker_state: AttackerState.new(source.id),
      rules: [%RemoteServiceExploitation{}],
      run_count: 1,
      iteration_count: 1,
      seed: 42
    }

    plan = Strategy.rank(strategy, [PatchVulnerability], graph, 1)

    assert [%PatchVulnerability{edge_id: "vulnerability"}] = plan
    assert plan == Strategy.rank(strategy, [PatchVulnerability], graph, 1)
  end

  test "returns no plan without eligible defenses" do
    source = GraphFixtures.node("source", Host, %{"name" => "source"})
    graph = GraphFixtures.graph([source], [])

    strategy = %SimulatedAnnealingStrategy{
      initial_attacker_state: AttackerState.new(source.id),
      rules: [%RemoteServiceExploitation{}],
      run_count: 1,
      iteration_count: 1,
      seed: 42
    }

    assert Strategy.rank(strategy, [PatchVulnerability], graph, 1) == []
  end

  test "returns no plan unless the joint modeled score strictly improves the baseline" do
    {graph, source} = unreachable_vulnerability_graph()

    strategy = %SimulatedAnnealingStrategy{
      initial_attacker_state: AttackerState.new(source.id),
      rules: [%RemoteServiceExploitation{}],
      run_count: 1,
      iteration_count: 1,
      seed: 42
    }

    assert Strategy.rank(strategy, [PatchVulnerability], graph, 1) == []
  end

  test "optimizer applies the full jointly selected plan in order" do
    {graph, source} = multi_target_graph()

    strategy = %SimulatedAnnealingStrategy{
      initial_attacker_state: AttackerState.new(source.id),
      rules: [%RemoteServiceExploitation{}],
      run_count: 1,
      iteration_count: 1,
      seed: 42
    }

    default_actions = [BlockSegmentReachability, PatchVulnerability, RevokeCredential]
    plan = Strategy.rank(strategy, default_actions, graph, 2)

    assert [first, second] = plan
    refute first == second

    result = Optimizer.apply(graph, strategy, 2)

    assert result.budget_used == 2
    assert Enum.map(result.actions, & &1.edge_id) == Enum.map(plan, & &1.edge_id)
    assert Strategy.plan?(strategy) == true
  end

  defp graph do
    source = GraphFixtures.node("source", Host, %{"name" => "source"})
    target = GraphFixtures.node("target", Host, %{"name" => "target"})
    source_segment = segment("source-segment")
    target_segment = segment("target-segment")

    service =
      GraphFixtures.node("service", Service, %{
        "name" => "service",
        "protocol" => "tcp",
        "port" => 443
      })

    vulnerability =
      GraphFixtures.node("vulnerability", Vulnerability, %{
        "identifier" => "CVE-0001",
        "cvss" => cvss(),
        "exploit_probability" => 1.0
      })

    graph =
      GraphFixtures.graph(
        [source_segment, target_segment, source, target, service, vulnerability],
        [
          GraphFixtures.edge("contains-source", source_segment, source, Contains),
          GraphFixtures.edge("contains-target", target_segment, target, Contains),
          GraphFixtures.edge(
            "policy",
            source_segment,
            target_segment,
            SegmentReachability,
            %{"protocol" => "tcp"}
          ),
          GraphFixtures.edge("runs", target, service, Runs),
          GraphFixtures.edge(
            "vulnerability",
            service,
            vulnerability,
            HasVulnerability,
            privileges()
          )
        ]
      )

    {graph, source}
  end

  defp unreachable_vulnerability_graph do
    source = GraphFixtures.node("source", Host, %{"name" => "source"})
    isolated = GraphFixtures.node("isolated", Host, %{"name" => "isolated"})
    source_segment = segment("source-segment")
    isolated_segment = segment("isolated-segment")

    service =
      GraphFixtures.node("service", Service, %{
        "name" => "svc",
        "protocol" => "tcp",
        "port" => 443
      })

    vulnerability =
      GraphFixtures.node("vulnerability", Vulnerability, %{
        "identifier" => "CVE-0001",
        "cvss" => cvss(),
        "exploit_probability" => 1.0
      })

    graph =
      GraphFixtures.graph(
        [source_segment, isolated_segment, source, isolated, service, vulnerability],
        [
          GraphFixtures.edge("contains-source", source_segment, source, Contains),
          GraphFixtures.edge("contains-isolated", isolated_segment, isolated, Contains),
          GraphFixtures.edge("runs", isolated, service, Runs),
          GraphFixtures.edge(
            "vulnerability",
            service,
            vulnerability,
            HasVulnerability,
            privileges()
          )
        ]
      )

    {graph, source}
  end

  defp multi_target_graph do
    source = GraphFixtures.node("source", Host, %{"name" => "source"})
    host_a = GraphFixtures.node("host-a", Host, %{"name" => "a"})
    host_b = GraphFixtures.node("host-b", Host, %{"name" => "b"})
    source_segment = segment("source-segment")
    segment_a = segment("segment-a")
    segment_b = segment("segment-b")
    service_a = service("service-a")
    service_b = service("service-b")
    vulnerability_a = vulnerability("vulnerability-a")
    vulnerability_b = vulnerability("vulnerability-b")

    graph =
      GraphFixtures.graph(
        [
          source_segment,
          segment_a,
          segment_b,
          source,
          host_a,
          host_b,
          service_a,
          service_b,
          vulnerability_a,
          vulnerability_b
        ],
        [
          GraphFixtures.edge("contains-source", source_segment, source, Contains),
          GraphFixtures.edge("contains-a", segment_a, host_a, Contains),
          GraphFixtures.edge("contains-b", segment_b, host_b, Contains),
          GraphFixtures.edge(
            "policy-a",
            source_segment,
            segment_a,
            SegmentReachability,
            policy()
          ),
          GraphFixtures.edge(
            "policy-b",
            source_segment,
            segment_b,
            SegmentReachability,
            policy()
          ),
          GraphFixtures.edge("runs-a", host_a, service_a, Runs),
          GraphFixtures.edge("runs-b", host_b, service_b, Runs),
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
          )
        ]
      )

    {graph, source}
  end

  defp service(id),
    do: GraphFixtures.node(id, Service, %{"name" => id, "protocol" => "tcp", "port" => 443})

  defp vulnerability(id) do
    GraphFixtures.node(id, Vulnerability, %{
      "identifier" => id,
      "cvss" => cvss(),
      "exploit_probability" => 1.0
    })
  end

  defp policy, do: %{"protocol" => "tcp"}

  defp segment(id),
    do: GraphFixtures.node(id, NetworkSegment, %{"name" => id})

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
