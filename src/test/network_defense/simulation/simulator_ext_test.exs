defmodule NetworkDefense.Simulation.SimulatorExtTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Actions.Action
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Credential
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Registry, as: NodeRegistry
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Relationships.AuthenticatesTo
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Relationships.StoresCredential
  alias NetworkDefense.Rules.RemoteServiceExploitation
  alias NetworkDefense.Rules.LocalVulnerabilityExploitation
  alias NetworkDefense.Rules.AcquireCredentialRule
  alias NetworkDefense.Rules.ReuseCredentialRule
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulation.Simulator

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

  test "actions are sorted deterministically by inspect of their key" do
    {graph, source_host, _target_host, _service, _vulnerability} = vulnerable_service_graph()

    attacker_state = AttackerState.new(source_host.id)

    simulation =
      Run.new(
        graph: graph,
        initial_attacker_state: attacker_state,
        rules: [%RemoteServiceExploitation{}]
      )

    actions = Simulator.get_possible_actions(simulation)
    assert actions != []

    keys = Enum.map(actions, &Action.key/1)
    string_keys = Enum.map(keys, &inspect/1)
    assert string_keys == Enum.sort(string_keys)
  end

  defp vulnerable_service_graph do
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
        edge("reachable", source_host, service, NetworkReachability, %{}),
        edge("runs", target_host, service, Runs),
        edge("vulnerability", service, vulnerability, HasVulnerability, %{
          "required_privilege" => "none",
          "granted_privilege" => "user"
        })
      ])

    {graph, source_host, target_host, service, vulnerability}
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

  defp graph(nodes, edges) do
    graph = %Graph{id: "graph", nodes: [], adjacency_list: %{}}
    graph = Enum.reduce(nodes, graph, &Graph.add_node(&2, &1))
    Enum.reduce(edges, graph, &Graph.add_edge(&2, &1))
  end

  defp node(id, type, data) do
    %Node{id: id, graph_id: "graph", type: NodeRegistry.type_for(type), data: data}
  end

  defp edge(id, from, to, type, extra_data \\ %{}) do
    %Edge{
      id: id,
      graph_id: "graph",
      from_id: from.id,
      to_id: to.id,
      type: RelationshipRegistry.type_for(type),
      data: extra_data
    }
  end

  defp build_node(graph, type, data) do
    %Node{
      id: Ecto.UUID.generate(),
      graph_id: graph.id,
      type: NodeRegistry.type_for(type),
      data: data,
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    }
  end
end
