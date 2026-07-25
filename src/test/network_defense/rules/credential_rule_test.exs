defmodule NetworkDefense.Rules.CredentialRuleTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Actions.Action
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Nodes.Credential
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Relationships.AuthenticatesTo
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Relationships.StoresCredential
  alias NetworkDefense.Rules.AcquireCredentialRule
  alias NetworkDefense.Rules.LocalVulnerabilityExploitation
  alias NetworkDefense.Rules.ReuseCredentialRule
  alias NetworkDefense.Rules.RemoteServiceExploitation
  alias NetworkDefense.Rules.Rule
  alias NetworkDefense.Simulation.Run

  import NetworkDefense.GraphFixtures

  describe "AcquireCredentialRule" do
    test "acquires credential from host with required privilege" do
      {graph, host, credential} = credential_graph()
      attacker_state = AttackerState.new(host.id, :user)
      simulation = Run.new(graph: graph, initial_attacker_state: attacker_state)

      assert [action] = Rule.evaluate(%AcquireCredentialRule{}, simulation)
      assert action.credential.id == credential.id

      result = Action.execute(action, attacker_state)
      assert AttackerState.has_credential?(result, credential.id)
    end

    test "does not acquire credential when required privilege not held" do
      host = node("host", Host, %{"name" => "bastion-01"})

      cred =
        node("cred", Credential, %{"identifier" => "admin-key", "credential_type" => "ssh_key"})

      graph =
        graph([host, cred], [
          edge("stores", host, cred, StoresCredential, %{"required_privilege" => "administrator"})
        ])

      attacker_state = AttackerState.new(host.id, :user)
      simulation = Run.new(graph: graph, initial_attacker_state: attacker_state)

      assert Rule.evaluate(%AcquireCredentialRule{}, simulation) == []
    end
  end

  describe "ReuseCredentialRule" do
    test "reuses credential to gain privilege on target host" do
      # Setup: attacker has foothold on source with reachability to service
      # and has matching credential that authenticates to the service
      source_host = node("source", Host, %{"name" => "internet"})
      target_host = node("target", Host, %{"name" => "web-01"})
      service = node("svc", Service, %{"name" => "nginx", "protocol" => "tcp", "port" => 443})

      credential =
        node("cred", Credential, %{"identifier" => "deploy-key", "credential_type" => "ssh_key"})

      graph =
        graph([source_host, target_host, service, credential], [
          edge("reach", source_host, service, NetworkReachability),
          edge("runs", target_host, service, Runs),
          edge("auth", credential, service, AuthenticatesTo, %{
            "granted_privilege" => "administrator"
          })
        ])

      attacker_state =
        AttackerState.new(source_host.id, :user)
        |> AttackerState.add_credential(credential.id)

      simulation = Run.new(graph: graph, initial_attacker_state: attacker_state)

      assert [action] = Rule.evaluate(%ReuseCredentialRule{}, simulation)
      assert action.credential.id == credential.id
      assert action.target_host.id == target_host.id
      assert action.granted_privilege == :administrator

      result = Action.execute(action, attacker_state)
      assert target_host.id in AttackerState.foothold_nodes(result)
      assert AttackerState.privilege_for(result, target_host.id) == :administrator
    end

    test "does not emit without matching credential" do
      source_host = node("source", Host, %{"name" => "internet"})
      target_host = node("target", Host, %{"name" => "web-01"})
      service = node("svc", Service, %{"name" => "nginx", "protocol" => "tcp", "port" => 443})

      graph =
        graph([source_host, target_host, service], [
          edge("reach", source_host, service, NetworkReachability),
          edge("runs", target_host, service, Runs)
        ])

      attacker_state = AttackerState.new(source_host.id, :user)
      simulation = Run.new(graph: graph, initial_attacker_state: attacker_state)

      assert Rule.evaluate(%ReuseCredentialRule{}, simulation) == []
    end
  end

  describe "LocalVulnerabilityExploitation" do
    test "exploits local vulnerability on host" do
      host = node("host", Host, %{"name" => "web-01"})

      vuln =
        node("vuln", Vulnerability, %{
          "identifier" => "CVE-0001",
          "cvss_score" => 7.5,
          "exploit_probability" => 1.0
        })

      graph =
        graph([host, vuln], [
          edge("hv", host, vuln, HasVulnerability, %{
            "required_privilege" => "user",
            "granted_privilege" => "administrator"
          })
        ])

      attacker_state = AttackerState.new(host.id, :user)
      simulation = Run.new(graph: graph, initial_attacker_state: attacker_state)

      assert [action] = Rule.evaluate(%LocalVulnerabilityExploitation{}, simulation)
      assert action.vulnerability_node.id == vuln.id
      assert action.granted_privilege == :administrator

      result = Action.execute(action, attacker_state)
      assert host.id in AttackerState.foothold_nodes(result)
      assert AttackerState.privilege_for(result, host.id) == :administrator
    end

    test "does not exploit when required privilege not held" do
      host = node("host", Host, %{"name" => "web-01"})

      vuln =
        node("vuln", Vulnerability, %{
          "identifier" => "CVE-0001",
          "cvss_score" => 7.5,
          "exploit_probability" => 1.0
        })

      graph =
        graph([host, vuln], [
          edge("hv", host, vuln, HasVulnerability, %{
            "required_privilege" => "administrator",
            "granted_privilege" => "administrator"
          })
        ])

      attacker_state = AttackerState.new(host.id, :user)
      simulation = Run.new(graph: graph, initial_attacker_state: attacker_state)

      assert Rule.evaluate(%LocalVulnerabilityExploitation{}, simulation) == []
    end
  end

  describe "RemoteServiceExploitation protocol matching" do
    test "matches when reachability protocol matches service" do
      {graph, source_host, _target_host, service, _vulnerability} =
        vulnerable_service_graph("tcp")

      attacker_state = AttackerState.new(source_host.id)
      simulation = Run.new(graph: graph, initial_attacker_state: attacker_state)

      assert [action] = Rule.evaluate(%RemoteServiceExploitation{}, simulation)
      assert action.service.id == service.id
    end

    test "matches when reachability protocol is any" do
      {graph, source_host, _target_host, service, _vulnerability} =
        vulnerable_service_graph("any")

      attacker_state = AttackerState.new(source_host.id)
      simulation = Run.new(graph: graph, initial_attacker_state: attacker_state)

      assert [action] = Rule.evaluate(%RemoteServiceExploitation{}, simulation)
      assert action.service.id == service.id
    end

    test "does not match when protocol differs" do
      {graph, source_host, _target_host, _service, _vulnerability} =
        vulnerable_service_graph("udp")

      attacker_state = AttackerState.new(source_host.id)
      simulation = Run.new(graph: graph, initial_attacker_state: attacker_state)

      assert Rule.evaluate(%RemoteServiceExploitation{}, simulation) == []
    end
  end

  defp vulnerable_service_graph(reachability_protocol) do
    source_host = node("source", Host, %{"name" => "internet"})
    target_host = node("target", Host, %{"name" => "web-01"})
    service = node("service", Service, %{"name" => "nginx", "protocol" => "tcp", "port" => 443})

    vulnerability =
      node("vulnerability", Vulnerability, %{
        "identifier" => "CVE-2024-0001",
        "cvss_score" => 7.5,
        "exploit_probability" => 1.0
      })

    graph =
      graph([source_host, target_host, service, vulnerability], [
        edge("reachable", source_host, service, NetworkReachability, %{
          "protocol" => reachability_protocol
        }),
        edge("runs", target_host, service, Runs),
        edge("vulnerability", service, vulnerability, HasVulnerability, %{
          "required_privilege" => "none",
          "granted_privilege" => "user"
        })
      ])

    {graph, source_host, target_host, service, vulnerability}
  end

  defp credential_graph do
    host = node("host", Host, %{"name" => "bastion-01"})

    credential =
      node("cred", Credential, %{"identifier" => "admin-key", "credential_type" => "ssh_key"})

    graph =
      graph([host, credential], [
        edge("stores", host, credential, StoresCredential, %{"required_privilege" => "user"})
      ])

    {graph, host, credential}
  end
end
