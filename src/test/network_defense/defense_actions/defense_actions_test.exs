defmodule NetworkDefense.DefenseActions.DefenseActionsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.DefenseActions.BlockReachability
  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.DefenseActions.RevokeCredential
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

  describe "BlockReachability" do
    test "removes one edge" do
      graph = reachability_graph()
      [edge] = Graph.edges(graph)

      action = %BlockReachability{edge_id: edge.id}
      assert DefenseAction.cost(action) == 1

      new_graph = DefenseAction.apply(action, graph)
      assert Graph.edges(new_graph) == []
    end
  end

  describe "PatchVulnerability" do
    test "removes one HasVulnerability edge" do
      graph = vulnerability_graph()

      vuln_edges =
        Enum.filter(
          Graph.edges(graph),
          &(&1.type == HasVulnerability)
        )

      [edge] = vuln_edges

      action = %PatchVulnerability{edge_id: edge.id}
      assert DefenseAction.cost(action) == 1

      new_graph = DefenseAction.apply(action, graph)

      remaining_vuln =
        Enum.filter(
          Graph.edges(new_graph),
          &(&1.type == HasVulnerability)
        )

      assert remaining_vuln == []
    end
  end

  describe "RevokeCredential" do
    test "removes all AuthenticatesTo edges from credential" do
      graph = credential_auth_graph()
      cred = find_node(graph, Credential)

      # Should have 2 AuthenticatesTo edges initially
      auth_edges_before =
        Enum.filter(
          Graph.edges(graph),
          &(&1.type == AuthenticatesTo)
        )

      assert length(auth_edges_before) == 2

      action = %RevokeCredential{credential_id: cred.id}
      assert DefenseAction.cost(action) == 1

      new_graph = DefenseAction.apply(action, graph)

      auth_edges_after =
        Enum.filter(
          Graph.edges(new_graph),
          &(&1.type == AuthenticatesTo)
        )

      assert auth_edges_after == []

      # Credential itself still exists
      assert find_node(new_graph, Credential) != nil
    end
  end

  defp reachability_graph do
    host = node("host", Host, %{"name" => "h1"})
    svc = node("svc", Service, %{"name" => "nginx", "protocol" => "tcp", "port" => 443})

    edge = %Edge{
      id: "e1",
      graph_id: "g",
      from_id: host.id,
      to_id: svc.id,
      type: RelationshipRegistry.type_for(NetworkReachability),
      data: %{}
    }

    graph([host, svc], [edge])
  end

  defp vulnerability_graph do
    svc = node("svc", Service, %{"name" => "nginx", "protocol" => "tcp", "port" => 443})

    vuln =
      node("vuln", Vulnerability, %{
        "identifier" => "CVE-0001",
        "cvss_score" => 5.0,
        "exploit_probability" => 0.5
      })

    edge = %Edge{
      id: "e1",
      graph_id: "g",
      from_id: svc.id,
      to_id: vuln.id,
      type: RelationshipRegistry.type_for(HasVulnerability),
      data: %{"required_privilege" => "none", "granted_privilege" => "user"}
    }

    graph([svc, vuln], [edge])
  end

  defp credential_auth_graph do
    cred = node("cred", Credential, %{"identifier" => "key-1", "credential_type" => "ssh_key"})
    svc1 = node("svc1", Service, %{"name" => "ssh", "protocol" => "tcp", "port" => 22})
    svc2 = node("svc2", Service, %{"name" => "git", "protocol" => "tcp", "port" => 22})

    auth1 = %Edge{
      id: "auth1",
      graph_id: "g",
      from_id: cred.id,
      to_id: svc1.id,
      type: RelationshipRegistry.type_for(AuthenticatesTo),
      data: %{"granted_privilege" => "administrator"}
    }

    auth2 = %Edge{
      id: "auth2",
      graph_id: "g",
      from_id: cred.id,
      to_id: svc2.id,
      type: RelationshipRegistry.type_for(AuthenticatesTo),
      data: %{"granted_privilege" => "user"}
    }

    graph([cred, svc1, svc2], [auth1, auth2])
  end

  defp graph(nodes, edges) do
    graph = %Graph{id: "g", nodes: [], adjacency_list: %{}}
    graph = Enum.reduce(nodes, graph, &Graph.add_node(&2, &1))
    Enum.reduce(edges, graph, &Graph.add_edge(&2, &1))
  end

  defp node(id, type, data) do
    %Node{id: id, graph_id: "g", type: NodeRegistry.type_for(type), data: data}
  end

  defp find_node(graph, type) do
    Enum.find(Graph.nodes(graph), &(&1.type == type))
  end
end
