defmodule NetworkDefense.Optimization.SimulationInformedStrategyTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, Service, Vulnerability}
  alias NetworkDefense.Optimization.{SimulationInformedStrategy, Strategy}
  alias NetworkDefense.Relationships.{HasVulnerability, NetworkReachability, Runs}
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

  defp graph do
    source = GraphFixtures.node("source", Host, %{"name" => "internet"})
    host_a = GraphFixtures.node("host-a", Host, %{"name" => "a"})
    host_b = GraphFixtures.node("host-b", Host, %{"name" => "b"})
    host_c = GraphFixtures.node("host-c", Host, %{"name" => "c"})
    service_a = service("service-a")
    service_b = service("service-b")
    service_c = service("service-c")
    vulnerability_a = vulnerability("vulnerability-a")
    vulnerability_b = vulnerability("vulnerability-b")
    vulnerability_c = vulnerability("vulnerability-c")

    graph =
      GraphFixtures.graph(
        [
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
          GraphFixtures.edge("reachability-a", source, service_a, NetworkReachability),
          GraphFixtures.edge("runs-a", host_a, service_a, Runs),
          GraphFixtures.edge(
            "vulnerability-a",
            service_a,
            vulnerability_a,
            HasVulnerability,
            privileges()
          ),
          GraphFixtures.edge("reachability-b", host_a, service_b, NetworkReachability),
          GraphFixtures.edge("runs-b", host_b, service_b, Runs),
          GraphFixtures.edge(
            "vulnerability-b",
            service_b,
            vulnerability_b,
            HasVulnerability,
            privileges()
          ),
          GraphFixtures.edge("reachability-c", source, service_c, NetworkReachability),
          GraphFixtures.edge("runs-c", host_c, service_c, Runs),
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
