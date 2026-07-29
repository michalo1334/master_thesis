defmodule NetworkDefense.Graph.SemanticEndpointTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Credential
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Relationships.AuthenticatesTo
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Relationships.StoresCredential

  describe "semantic endpoint validation on graph replacement" do
    test "accepts valid HasVulnerability Service -> Vulnerability edge" do
      graph = insert_graph()
      service = insert_node(graph, Service, %{"name" => "svc", "protocol" => "tcp", "port" => 80})
      vuln = insert_vuln_node(graph, "CVE-0001")

      attrs = %{
        "title" => graph.title,
        "nodes" => [node_attrs(service), node_attrs(vuln)],
        "edges" => [
          edge_attrs(Ecto.UUID.generate(), service.id, vuln.id, HasVulnerability, %{
            "required_privilege" => "none",
            "granted_privilege" => "user"
          })
        ]
      }

      assert {:ok, _} = Graphs.replace(graph.id, 1, attrs)
    end

    test "accepts valid HasVulnerability Host -> Vulnerability edge" do
      graph = insert_graph()
      host = insert_node(graph, Host, %{"name" => "host-1"})
      vuln = insert_vuln_node(graph, "CVE-0002")

      attrs = %{
        "title" => graph.title,
        "nodes" => [node_attrs(host), node_attrs(vuln)],
        "edges" => [
          edge_attrs(Ecto.UUID.generate(), host.id, vuln.id, HasVulnerability, %{
            "required_privilege" => "user",
            "granted_privilege" => "administrator"
          })
        ]
      }

      assert {:ok, _} = Graphs.replace(graph.id, 1, attrs)
    end

    test "accepts valid StoresCredential Host -> Credential edge" do
      graph = insert_graph()
      host = insert_node(graph, Host, %{"name" => "host-1"})
      cred = insert_cred_node(graph, "key-1", "ssh_key")

      attrs = %{
        "title" => graph.title,
        "nodes" => [node_attrs(host), node_attrs(cred)],
        "edges" => [
          edge_attrs(Ecto.UUID.generate(), host.id, cred.id, StoresCredential, %{
            "required_privilege" => "user"
          })
        ]
      }

      assert {:ok, _} = Graphs.replace(graph.id, 1, attrs)
    end

    test "accepts valid AuthenticatesTo Credential -> Service edge" do
      graph = insert_graph()
      cred = insert_cred_node(graph, "key-1", "ssh_key")
      service = insert_node(graph, Service, %{"name" => "svc", "protocol" => "tcp", "port" => 22})

      attrs = %{
        "title" => graph.title,
        "nodes" => [node_attrs(cred), node_attrs(service)],
        "edges" => [
          edge_attrs(Ecto.UUID.generate(), cred.id, service.id, AuthenticatesTo, %{
            "granted_privilege" => "administrator"
          })
        ]
      }

      assert {:ok, _} = Graphs.replace(graph.id, 1, attrs)
    end

    test "rejects NetworkReachability between two hosts" do
      graph = insert_graph()
      host1 = insert_node(graph, Host, %{"name" => "host-1"})
      host2 = insert_node(graph, Host, %{"name" => "host-2"})

      attrs = %{
        "title" => graph.title,
        "nodes" => [node_attrs(host1), node_attrs(host2)],
        "edges" => [
          edge_attrs(Ecto.UUID.generate(), host1.id, host2.id, NetworkReachability)
        ]
      }

      assert {:error, :invalid_graph} = Graphs.replace(graph.id, 1, attrs)
    end

    test "rejects Runs between two services" do
      graph = insert_graph()
      svc1 = insert_node(graph, Service, %{"name" => "svc1", "protocol" => "tcp", "port" => 80})
      svc2 = insert_node(graph, Service, %{"name" => "svc2", "protocol" => "tcp", "port" => 443})

      attrs = %{
        "title" => graph.title,
        "nodes" => [node_attrs(svc1), node_attrs(svc2)],
        "edges" => [
          edge_attrs(Ecto.UUID.generate(), svc1.id, svc2.id, Runs)
        ]
      }

      assert {:error, :invalid_graph} = Graphs.replace(graph.id, 1, attrs)
    end

    test "rejects HasVulnerability from a Vulnerability node" do
      graph = insert_graph()
      vuln1 = insert_vuln_node(graph, "CVE-0001")
      vuln2 = insert_vuln_node(graph, "CVE-0002")

      attrs = %{
        "title" => graph.title,
        "nodes" => [node_attrs(vuln1), node_attrs(vuln2)],
        "edges" => [
          edge_attrs(Ecto.UUID.generate(), vuln1.id, vuln2.id, HasVulnerability, %{
            "required_privilege" => "none",
            "granted_privilege" => "user"
          })
        ]
      }

      assert {:error, :invalid_graph} = Graphs.replace(graph.id, 1, attrs)
    end

    test "rejects StoresCredential from a Service node" do
      graph = insert_graph()
      svc = insert_node(graph, Service, %{"name" => "svc", "protocol" => "tcp", "port" => 80})
      cred = insert_cred_node(graph, "key-1", "ssh_key")

      attrs = %{
        "title" => graph.title,
        "nodes" => [node_attrs(svc), node_attrs(cred)],
        "edges" => [
          edge_attrs(Ecto.UUID.generate(), svc.id, cred.id, StoresCredential, %{
            "required_privilege" => "user"
          })
        ]
      }

      assert {:error, :invalid_graph} = Graphs.replace(graph.id, 1, attrs)
    end

    test "rejects AuthenticatesTo from a Host node" do
      graph = insert_graph()
      host = insert_node(graph, Host, %{"name" => "host-1"})
      svc = insert_node(graph, Service, %{"name" => "svc", "protocol" => "tcp", "port" => 80})

      attrs = %{
        "title" => graph.title,
        "nodes" => [node_attrs(host), node_attrs(svc)],
        "edges" => [
          edge_attrs(Ecto.UUID.generate(), host.id, svc.id, AuthenticatesTo, %{
            "granted_privilege" => "user"
          })
        ]
      }

      assert {:error, :invalid_graph} = Graphs.replace(graph.id, 1, attrs)
    end
  end

  describe "in-memory semantic validation" do
    test "add_edge raises for invalid endpoint types" do
      graph = Graph.new("test")
      host = build_node(graph, Host, %{"name" => "host-1"})
      svc = build_node(graph, Service, %{"name" => "svc", "protocol" => "tcp", "port" => 80})

      graph = graph |> Graph.add_node(host) |> Graph.add_node(svc)

      assert_raise ArgumentError, ~r/not valid/, fn ->
        Graph.add_edge(graph, svc, host, %{type: Atom.to_string(NetworkReachability), data: %{}})
      end
    end

    test "add_edge accepts valid endpoint types" do
      graph = Graph.new("test")
      host = build_node(graph, Host, %{"name" => "host-1"})
      svc = build_node(graph, Service, %{"name" => "svc", "protocol" => "tcp", "port" => 80})

      graph = graph |> Graph.add_node(host) |> Graph.add_node(svc)

      graph =
        Graph.add_edge(graph, host, svc, %{type: Atom.to_string(NetworkReachability), data: %{}})

      assert length(Graph.edges(graph)) == 1
    end
  end

  defp insert_graph do
    %Graph{}
    |> Graph.changeset(%{title: "test-graph"})
    |> Repo.insert!()
  end

  defp insert_node(graph, type, data) do
    %Node{graph_id: graph.id}
    |> Node.changeset(%{
      type: Atom.to_string(type),
      data: data,
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    })
    |> Repo.insert!()
  end

  defp insert_vuln_node(graph, identifier) do
    insert_node(graph, Vulnerability, %{
      "identifier" => identifier,
      "cvss" => cvss(),
      "exploit_probability" => 0.5
    })
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

  defp insert_cred_node(graph, identifier, cred_type) do
    insert_node(graph, Credential, %{"identifier" => identifier, "credential_type" => cred_type})
  end

  defp node_attrs(node) do
    %{"id" => node.id, "type" => node.type, "data" => node.data, "view_data" => node.view_data}
  end

  defp edge_attrs(id, from_id, to_id, type, extra_data \\ %{}) do
    %{
      "id" => id,
      "from_id" => from_id,
      "to_id" => to_id,
      "type" => Atom.to_string(type),
      "data" => extra_data
    }
  end

  defp build_node(graph, type, data) do
    %Node{
      id: Ecto.UUID.generate(),
      graph_id: graph.id,
      type: Atom.to_string(type),
      data: data,
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    }
  end
end
