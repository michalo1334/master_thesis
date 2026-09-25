defmodule NetworkDefense.Graph.ContractsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.Contracts.Data.{
    AuthenticatesToData,
    CredentialData,
    NetworkSegmentData,
    CvssData,
    HasVulnerabilityData,
    MissionCapabilityData,
    RequiredServiceFlowData,
    SegmentReachabilityData,
    StoresCredentialData
  }

  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.Contracts.SaveGraphContract
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Nodes.{Host, NetworkSegment, Service}
  alias NetworkDefense.Relationships.{Contains, Runs}

  describe "CredentialData" do
    test "validates credential data" do
      assert {:ok, _} =
               CredentialData.validate(%{"identifier" => "key-1", "credential_type" => "ssh_key"})

      assert {:ok, _} =
               CredentialData.validate(%{
                 "identifier" => "pass-1",
                 "credential_type" => "password"
               })

      assert {:ok, _} =
               CredentialData.validate(%{"identifier" => "tok-1", "credential_type" => "token"})

      assert {:error, _} = CredentialData.validate(%{"identifier" => "key-1"})

      assert {:error, _} =
               CredentialData.validate(%{"identifier" => "key-1", "credential_type" => "invalid"})
    end
  end

  describe "NetworkSegmentData" do
    test "requires a name and accepts an optional CIDR" do
      assert {:ok, _} = NetworkSegmentData.validate(%{"name" => "DMZ", "cidr" => "10.0.0.0/24"})
      assert {:ok, _} = NetworkSegmentData.validate(%{"name" => "Internal"})

      assert {:error, _} =
               NetworkSegmentData.validate(%{"name" => "Invalid", "cidr" => "10.0.0.0/40"})

      assert {:error, _} = NetworkSegmentData.validate(%{})
    end
  end

  describe "StoresCredentialData" do
    test "validates required_privilege" do
      assert {:ok, _} = StoresCredentialData.validate(%{"required_privilege" => "user"})
      assert {:ok, _} = StoresCredentialData.validate(%{"required_privilege" => "administrator"})
      assert {:error, _} = StoresCredentialData.validate(%{})
      assert {:error, _} = StoresCredentialData.validate(%{"required_privilege" => "none"})
    end
  end

  describe "AuthenticatesToData" do
    test "validates granted_privilege" do
      assert {:ok, _} = AuthenticatesToData.validate(%{"granted_privilege" => "user"})
      assert {:ok, _} = AuthenticatesToData.validate(%{"granted_privilege" => "administrator"})
      assert {:error, _} = AuthenticatesToData.validate(%{})
    end
  end

  describe "HasVulnerabilityData" do
    test "validates privilege fields" do
      assert {:ok, _} =
               HasVulnerabilityData.validate(%{
                 "required_privilege" => "none",
                 "granted_privilege" => "user"
               })

      assert {:ok, _} =
               HasVulnerabilityData.validate(%{
                 "required_privilege" => "user",
                 "granted_privilege" => "administrator"
               })

      assert {:error, _} = HasVulnerabilityData.validate(%{"required_privilege" => "none"})

      assert {:error, _} =
               HasVulnerabilityData.validate(%{
                 "required_privilege" => "admin",
                 "granted_privilege" => "user"
               })
    end
  end

  describe "CvssData" do
    test "validates all CVSS v3.1 base metrics" do
      assert {:ok, _} = CvssData.validate(cvss())

      assert {:error, _} =
               CvssData.validate(Map.put(cvss(), "attack_vector", "internet"))

      assert {:error, _} = CvssData.validate(Map.delete(cvss(), "scope"))
    end
  end

  describe "SegmentReachabilityData" do
    test "validates protocol and optional ports" do
      assert {:ok, _} = SegmentReachabilityData.validate(%{"protocol" => "any"})
      assert {:ok, _} = SegmentReachabilityData.validate(%{"protocol" => "tcp"})
      assert {:ok, _} = SegmentReachabilityData.validate(%{"protocol" => "udp"})

      assert {:ok, _} =
               SegmentReachabilityData.validate(%{
                 "protocol" => "tcp",
                 "port_start" => 80,
                 "port_end" => 443
               })

      assert {:error, _} = SegmentReachabilityData.validate(%{})

      assert {:error, _} =
               SegmentReachabilityData.validate(%{"protocol" => "tcp", "port_start" => 80})

      assert {:error, _} =
               SegmentReachabilityData.validate(%{
                 "protocol" => "tcp",
                 "port_start" => 70_000,
                 "port_end" => 80_000
               })

      assert {:error, _} =
               SegmentReachabilityData.validate(%{
                 "protocol" => "tcp",
                 "port_start" => 443,
                 "port_end" => 80
               })
    end
  end

  describe "RequiredServiceFlowData" do
    test "requires a source segment and a target service" do
      segment_id = Ecto.UUID.generate()
      service_id = Ecto.UUID.generate()

      assert {:ok, _} =
               RequiredServiceFlowData.validate(%{
                 "source_segment_id" => segment_id,
                 "target_service_id" => service_id
               })

      assert {:error, _} = RequiredServiceFlowData.validate(%{"source_segment_id" => segment_id})
      assert {:error, _} = RequiredServiceFlowData.validate(%{"target_service_id" => service_id})
      assert {:error, _} = RequiredServiceFlowData.validate(%{})

      assert {:error, _} =
               RequiredServiceFlowData.validate(%{
                 "source_segment_id" => "not-a-uuid",
                 "target_service_id" => service_id
               })
    end
  end

  describe "MissionCapabilityData" do
    test "accepts required service flows" do
      segment_id = Ecto.UUID.generate()
      service_id = Ecto.UUID.generate()

      assert {:ok, capability} =
               MissionCapabilityData.validate(%{
                 "name" => "Orders",
                 "impact_weight" => 2.0,
                 "min_operational_support" => 1,
                 "required_flows" => [
                   %{"source_segment_id" => segment_id, "target_service_id" => service_id}
                 ]
               })

      assert [%{source_segment_id: ^segment_id, target_service_id: ^service_id}] =
               capability.required_flows
    end

    test "rejects required flows with missing fields" do
      assert {:error, _} =
               MissionCapabilityData.validate(%{
                 "name" => "Orders",
                 "impact_weight" => 2.0,
                 "min_operational_support" => 1,
                 "required_flows" => [%{"source_segment_id" => Ecto.UUID.generate()}]
               })
    end
  end

  describe "GraphContract" do
    test "rejects invalid nested identifiers" do
      params = graph_params()

      invalid_params = [
        put_in(params, ["nodes", Access.at(0), "id"], "invalid"),
        put_in(params, ["edges", Access.at(0), "id"], "invalid"),
        put_in(params, ["edges", Access.at(0), "from_id"], "invalid"),
        put_in(params, ["edges", Access.at(0), "to_id"], "invalid")
      ]

      Enum.each(invalid_params, fn invalid_params ->
        assert {:error, _changeset} = GraphContract.validate(invalid_params)
      end)
    end
  end

  describe "GraphContract.to_domain/2" do
    test "converts a valid contract into a domain graph" do
      {params, ids} = complete_graph()

      assert {:ok, contract} = GraphContract.validate(params)
      assert {:ok, graph} = GraphContract.to_domain(contract)

      assert graph.id == contract.id
      assert graph.title == contract.title

      assert Graph.nodes(graph) |> Enum.map(& &1.type) |> Enum.sort() == [
               Host,
               NetworkSegment,
               Service
             ]

      assert Graph.edges(graph) |> Enum.map(& &1.type) |> Enum.sort() == [Contains, Runs]
      assert Graph.node(graph, ids.host).data.name == "host"
    end

    test "rejects incomplete ownership by default, accepts it with validate_membership: false" do
      {params, _ids} =
        complete_graph(Map.put(unplaced("extra"), "view_data", %{"x_pos" => 3, "y_pos" => 3}))

      assert {:ok, contract} = GraphContract.validate(params)

      assert {:error, changeset} = GraphContract.to_domain(contract)
      assert to_domain_error(changeset, :edges, "multiple_segments")

      assert {:ok, graph} = GraphContract.to_domain(contract, validate_membership: false)
      assert Enum.count(Graph.nodes(graph)) == 4
      assert Enum.count(Graph.edges(graph)) == 2
    end

    test "rejects a node with an unknown type" do
      {params, _ids} = complete_graph()
      {:ok, contract} = GraphContract.validate(params)

      unknown = %{Enum.at(contract.nodes, 0) | type: "Worm"}
      contract = %{contract | nodes: List.replace_at(contract.nodes, 0, unknown)}

      assert {:error, changeset} = GraphContract.to_domain(contract)
      assert to_domain_error(changeset, :nodes, "invalid_node")
    end

    test "rejects node data that is invalid for its type" do
      {params, _ids} = complete_graph()
      {:ok, contract} = GraphContract.validate(params)

      invalid = %{Enum.at(contract.nodes, 0) | data: %{}}
      contract = %{contract | nodes: List.replace_at(contract.nodes, 0, invalid)}

      assert {:error, changeset} = GraphContract.to_domain(contract)
      assert to_domain_error(changeset, :nodes, "invalid_node")
    end

    test "rejects an edge with an unknown type" do
      {params, _ids} = complete_graph()
      {:ok, contract} = GraphContract.validate(params)

      unknown = %{Enum.at(contract.edges, 0) | type: "FirewallRule"}
      contract = %{contract | edges: List.replace_at(contract.edges, 0, unknown)}

      assert {:error, changeset} =
               GraphContract.to_domain(contract, validate_membership: false)

      assert to_domain_error(changeset, :edges, "invalid_edge")
    end

    test "rejects duplicate node ids before hydration" do
      {params, _ids} = complete_graph()
      segment = Enum.at(params["nodes"], 0)
      params = put_in(params, ["nodes"], [segment] ++ params["nodes"])

      assert {:ok, contract} = GraphContract.validate(params)

      assert {:error, changeset} =
               GraphContract.to_domain(contract, validate_membership: false)

      assert to_domain_error(changeset, :nodes, "duplicate_ids")
    end

    test "rejects duplicate edge ids before hydration" do
      {params, _ids} = complete_graph()
      edge = Enum.at(params["edges"], 0)
      params = put_in(params, ["edges"], [edge] ++ params["edges"])

      assert {:ok, contract} = GraphContract.validate(params)

      assert {:error, changeset} =
               GraphContract.to_domain(contract, validate_membership: false)

      assert to_domain_error(changeset, :edges, "duplicate_ids")
    end

    test "rejects a contract that is missing its graph identity" do
      assert {:error, changeset} = GraphContract.to_domain(%GraphContract{id: nil, title: nil})

      assert to_domain_error(changeset, :id, "can't be blank")
      assert to_domain_error(changeset, :title, "can't be blank")
    end

    test "rejects nil node and edge lists" do
      contract = %GraphContract{
        id: Ecto.UUID.generate(),
        title: "Graph",
        nodes: nil,
        edges: nil
      }

      assert {:error, changeset} = GraphContract.to_domain(contract)

      assert to_domain_error(changeset, :nodes, "can't be blank")
      assert to_domain_error(changeset, :edges, "can't be blank")
    end

    test "rejects a graph id that is not a uuid" do
      contract = %GraphContract{id: "not-a-uuid", title: "Graph", nodes: [], edges: []}

      assert {:error, changeset} = GraphContract.to_domain(contract)
      assert to_domain_error(changeset, :id, "is invalid")
    end

    test "rejects node and edge values that are not lists of contracts" do
      graph_id = Ecto.UUID.generate()

      cases = [
        {%{id: graph_id, title: "Graph", nodes: %{"id" => "segment"}, edges: []}, :nodes},
        {%{id: graph_id, title: "Graph", nodes: [nil], edges: []}, :nodes},
        {%{id: graph_id, title: "Graph", nodes: [], edges: %{"id" => "edge"}}, :edges},
        {%{id: graph_id, title: "Graph", nodes: [], edges: [nil]}, :edges}
      ]

      Enum.each(cases, fn {attrs, field} ->
        assert {:error, changeset} = GraphContract.to_domain(struct(GraphContract, attrs))
        assert to_domain_error(changeset, field, "is invalid")
      end)
    end

    test "rejects a dangling edge endpoint even with validate_membership: false" do
      {params, %{host: host_id}} = complete_graph()

      dangling = %{
        "id" => Ecto.UUID.generate(),
        "from_id" => host_id,
        "to_id" => Ecto.UUID.generate(),
        "type" => "Runs",
        "data" => %{}
      }

      params = put_in(params, ["edges"], params["edges"] ++ [dangling])

      assert {:ok, contract} = GraphContract.validate(params)

      assert {:error, changeset} = GraphContract.to_domain(contract)
      assert to_domain_error(changeset, :edges, "invalid_endpoints")

      assert {:error, changeset} =
               GraphContract.to_domain(contract, validate_membership: false)

      assert to_domain_error(changeset, :edges, "invalid_endpoints")
    end

    test "rejects endpoints that do not match the relationship" do
      {params, %{host: host_id, service: service_id}} = complete_graph()

      reversed = %{
        "id" => Ecto.UUID.generate(),
        "from_id" => service_id,
        "to_id" => host_id,
        "type" => "Runs",
        "data" => %{}
      }

      params = put_in(params, ["edges"], params["edges"] ++ [reversed])

      assert {:ok, contract} = GraphContract.validate(params)

      assert {:error, changeset} =
               GraphContract.to_domain(contract, validate_membership: false)

      assert to_domain_error(changeset, :edges, "invalid_endpoints")
    end
  end

  describe "SaveGraphContract" do
    test "requires a base revision and excludes response-only fields" do
      params = Map.put(graph_params(), "revision_id", Ecto.UUID.generate())

      assert {:ok, graph} = SaveGraphContract.validate(params)

      assert %{"id" => _, "revision_id" => _, "title" => _, "nodes" => _, "edges" => _} =
               SaveGraphContract.to_params(graph)

      refute Map.has_key?(SaveGraphContract.to_params(graph), "parent_revision_id")
      refute Map.has_key?(SaveGraphContract.to_params(graph), "revision_number")
      refute Map.has_key?(SaveGraphContract.to_params(graph), "revision_kind")
      assert {:error, _changeset} = SaveGraphContract.validate(graph_params())
    end
  end

  defp graph_params do
    node_id = Ecto.UUID.generate()
    target_id = Ecto.UUID.generate()

    %{
      "id" => Ecto.UUID.generate(),
      "title" => "Graph",
      "nodes" => [
        %{
          "id" => node_id,
          "type" => "Host",
          "data" => %{"name" => "host"},
          "view_data" => %{"x_pos" => 0, "y_pos" => 0}
        }
      ],
      "edges" => [
        %{
          "id" => Ecto.UUID.generate(),
          "from_id" => node_id,
          "to_id" => target_id,
          "type" => "Runs",
          "data" => %{}
        }
      ]
    }
  end

  defp complete_graph, do: complete_graph(nil)

  defp complete_graph(unplaced_host) do
    segment_id = Ecto.UUID.generate()
    host_id = Ecto.UUID.generate()
    service_id = Ecto.UUID.generate()

    segment = %{
      "id" => segment_id,
      "type" => "NetworkSegment",
      "data" => %{"name" => "Segment"},
      "view_data" => %{"x_pos" => 0, "y_pos" => 0}
    }

    host = %{
      "id" => host_id,
      "type" => "Host",
      "data" => %{"name" => "host"},
      "view_data" => %{"x_pos" => 1, "y_pos" => 1}
    }

    service = %{
      "id" => service_id,
      "type" => "Service",
      "data" => %{"name" => "svc", "protocol" => "tcp", "port" => 443},
      "view_data" => %{"x_pos" => 2, "y_pos" => 2}
    }

    nodes = [segment, host, service]

    nodes =
      if unplaced_host,
        do: nodes ++ [Map.put(unplaced_host, "id", Ecto.UUID.generate())],
        else: nodes

    params = %{
      "id" => Ecto.UUID.generate(),
      "title" => "Graph",
      "nodes" => nodes,
      "edges" => [
        %{
          "id" => Ecto.UUID.generate(),
          "from_id" => segment_id,
          "to_id" => host_id,
          "type" => "Contains",
          "data" => %{}
        },
        %{
          "id" => Ecto.UUID.generate(),
          "from_id" => host_id,
          "to_id" => service_id,
          "type" => "Runs",
          "data" => %{}
        }
      ]
    }

    {params, %{segment: segment_id, host: host_id, service: service_id}}
  end

  defp unplaced(name) do
    %{"type" => "Host", "data" => %{"name" => name}}
  end

  defp to_domain_error(%Ecto.Changeset{errors: errors}, field, message) do
    errors =
      errors
      |> Keyword.fetch(field)
      |> case do
        {:ok, {msg, opts}} -> [{msg, opts}]
        {:ok, other} -> other
        :error -> []
      end

    assert [{^message, _opts}] = errors
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
