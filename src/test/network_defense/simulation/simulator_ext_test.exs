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

  test "simulation progresses by selecting one random action per iteration" do
    {graph, source_host, target_host, _service, _vuln} = full_exploit_graph()
    attacker_state = AttackerState.new(source_host.id, :administrator)

    rules = [
      %RemoteServiceExploitation{},
      %LocalVulnerabilityExploitation{},
      %AcquireCredentialRule{},
      %ReuseCredentialRule{}
    ]

    {_experiment, runs} =
      Simulator.run_experiment(
        graph,
        attacker_state,
        rules: rules,
        iteration_count: 5,
        seed: 42,
        run_count: 1
      )

    result = hd(runs)
    final_state = Run.current_attacker_state(result)
    footholds = AttackerState.foothold_nodes(final_state)
    assert target_host.id in footholds
  end

  test "stops early when no actions are available" do
    graph = Graph.new("empty")
    host = build_node(graph, Host, %{"name" => "isolated"})
    graph = Graph.add_node(graph, host)

    attacker_state = AttackerState.new(host.id)

    {_experiment, runs} =
      Simulator.run_experiment(
        graph,
        attacker_state,
        rules: [%RemoteServiceExploitation{}],
        iteration_count: 100,
        seed: 42,
        run_count: 1
      )

    assert Run.current_iteration(hd(runs)) == nil
  end

  test "reproduces a run from the same master seed" do
    {graph, source_host, _target_host, _service, _vuln} = full_exploit_graph()
    attacker_state = AttackerState.new(source_host.id, :administrator)

    opts = [
      rules: [%RemoteServiceExploitation{}],
      iteration_count: 3,
      seed: 42,
      run_count: 1
    ]

    {_experiment, [first_run]} = Simulator.run_experiment(graph, attacker_state, opts)
    {_experiment, [second_run]} = Simulator.run_experiment(graph, attacker_state, opts)

    assert first_run.seed == second_run.seed
    assert run_snapshot(first_run) == run_snapshot(second_run)
  end

  test "stops selecting an action after its attempt cap" do
    host = node("host", Host, %{"name" => "web-01"})

    vulnerability =
      node("vulnerability", Vulnerability, %{
        "identifier" => "CVE-2024-0001",
        "cvss" => cvss(),
        "exploit_probability" => 1.0
      })

    graph =
      graph([host, vulnerability], [
        edge("has-vulnerability", host, vulnerability, HasVulnerability, %{
          "required_privilege" => "user",
          "granted_privilege" => "administrator"
        })
      ])

    {_experiment, [run]} =
      Simulator.run_experiment(
        graph,
        AttackerState.new(host.id),
        rules: [%LocalVulnerabilityExploitation{}],
        iteration_count: 3,
        max_attempts: 2,
        seed: 42,
        run_count: 1
      )

    assert Enum.map(run.iterations, & &1.attempted_action.attempt_count) == [2, 1]
  end

  defp full_exploit_graph do
    source_host = node("source", Host, %{"name" => "internet"})
    target_host = node("target", Host, %{"name" => "web-01"})
    service = node("service", Service, %{"name" => "nginx", "protocol" => "tcp", "port" => 443})

    vulnerability =
      node("vulnerability", Vulnerability, %{
        "identifier" => "CVE-2024-0001",
        "cvss" => cvss(),
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

  defp run_snapshot(run) do
    Enum.map(run.iterations, fn iteration ->
      %{
        index: iteration.index,
        success?: iteration.success?,
        attempt_count: iteration.attempted_action.attempt_count,
        action_type: iteration.attempted_action.action_type,
        action_data: iteration.attempted_action.action_data,
        attacker_state: iteration.attacker_state
      }
    end)
  end

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
