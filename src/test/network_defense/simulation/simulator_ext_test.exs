defmodule NetworkDefense.Simulation.SimulatorExtTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Nodes.Credential
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Relationships.AuthenticatesTo
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Relationships.StoresCredential
  alias NetworkDefense.Rules.RemoteServiceExploitation
  alias NetworkDefense.Rules.LocalVulnerabilityExploitation
  alias NetworkDefense.Rules.AcquireCredentialRule
  alias NetworkDefense.Rules.ReuseCredentialRule
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulation.Simulator

  import NetworkDefense.GraphFixtures

  test "batch simulation runs all unique eligible actions each round" do
    {graph, source_host, target_host, _service, _vuln} = full_exploit_graph()
    attacker_state = AttackerState.new(source_host.id, :administrator)

    rules = [
      %RemoteServiceExploitation{},
      %LocalVulnerabilityExploitation{},
      %AcquireCredentialRule{},
      %ReuseCredentialRule{}
    ]

    result =
      Simulator.run(
        graph: graph,
        initial_attacker_state: attacker_state,
        rules: rules,
        iteration_count: 5,
        seed: 42
      )

    final_state = Run.current_attacker_state(result)
    # Should have progressed past the initial host
    footholds = AttackerState.foothold_nodes(final_state)
    assert target_host.id in footholds
  end

  test "stops early when no actions are available" do
    graph = Graph.new("empty")
    host = build_node(graph, Host, %{"name" => "isolated"})
    graph = Graph.add_node(graph, host)

    attacker_state = AttackerState.new(host.id)

    result =
      Simulator.run(
        graph: graph,
        initial_attacker_state: attacker_state,
        rules: [%RemoteServiceExploitation{}],
        iteration_count: 100,
        seed: 42
      )

    # No iterations should have been created since there are no paths
    assert Run.current_iteration(result) == nil
  end

  defp full_exploit_graph do
    source_host = node("source", Host, %{"name" => "internet"})
    target_host = node("target", Host, %{"name" => "web-01"})
    service = node("service", Service, %{"name" => "nginx", "protocol" => "tcp", "port" => 443})

    vulnerability =
      node("vulnerability", Vulnerability, %{
        "identifier" => "CVE-2024-0001",
        "cvss_score" => 7.5,
        "exploit_probability" => 1.0
      })

    credential =
      node("cred", Credential, %{"identifier" => "key-1", "credential_type" => "ssh_key"})

    graph =
      graph([source_host, target_host, service, vulnerability, credential], [
        edge("reachable", source_host, service, NetworkReachability, %{}),
        edge("runs", target_host, service, Runs),
        edge("vulnerability", service, vulnerability, HasVulnerability, %{
          "required_privilege" => "none",
          "granted_privilege" => "user"
        }),
        edge("stores", source_host, credential, StoresCredential, %{
          "required_privilege" => "administrator"
        }),
        edge("auth", credential, service, AuthenticatesTo, %{
          "granted_privilege" => "administrator"
        })
      ])

    {graph, source_host, target_host, service, vulnerability}
  end
end
