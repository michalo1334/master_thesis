defmodule NetworkDefense.Optimization.SimulatedAnnealingStrategyTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, Service, Vulnerability}
  alias NetworkDefense.Optimization.{SimulatedAnnealingStrategy, Strategy}
  alias NetworkDefense.Relationships.{HasVulnerability, NetworkReachability, Runs}
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

  defp graph do
    source = GraphFixtures.node("source", Host, %{"name" => "source"})
    target = GraphFixtures.node("target", Host, %{"name" => "target"})

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
      GraphFixtures.graph([source, target, service, vulnerability], [
        GraphFixtures.edge("reachability", source, service, NetworkReachability),
        GraphFixtures.edge("runs", target, service, Runs),
        GraphFixtures.edge(
          "vulnerability",
          service,
          vulnerability,
          HasVulnerability,
          privileges()
        )
      ])

    {graph, source}
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
