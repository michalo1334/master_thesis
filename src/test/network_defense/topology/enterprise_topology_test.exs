defmodule NetworkDefense.Topology.EnterpriseTopologyTest do
  use NetworkDefense.DataCase

  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Nodes.{Host, NetworkSegment, Vulnerability}

  alias NetworkDefense.Relationships.{
    Contains,
    HasVulnerability,
    NetworkReachability,
    SegmentReachability
  }

  alias NetworkDefense.Topology.{EnterpriseTopology, VulnerabilityCatalog}

  describe "generate/1" do
    test "is deterministic and contains the requested enterprise hosts plus internet ingress" do
      first = EnterpriseTopology.generate(title: "topo", hosts: 12, seed: 42)
      second = EnterpriseTopology.generate(title: "topo", hosts: 12, seed: 42)

      assert host_names(first) == host_names(second)
      assert Enum.count_until(host_names(first), 14) == 13
      assert "internet" in host_names(first)
    end

    test "always includes hosts for every required zone and role" do
      graph = EnterpriseTopology.generate(hosts: EnterpriseTopology.minimum_hosts(), seed: 1)
      names = host_names(graph)

      assert Enum.any?(names, &String.starts_with?(&1, "dmz-web-"))
      assert Enum.any?(names, &String.starts_with?(&1, "internal-api-"))
      assert Enum.any?(names, &String.starts_with?(&1, "restricted-db-"))
      assert Enum.any?(names, &String.starts_with?(&1, "mgmt-bastion-"))
    end

    test "assigns every host to one deterministic network segment" do
      graph = EnterpriseTopology.generate(hosts: EnterpriseTopology.minimum_hosts(), seed: 1)

      segments =
        graph
        |> Graph.nodes()
        |> Enum.filter(&(&1.type == NetworkSegment))

      assert Enum.map(segments, & &1.data.name) == [
               "External",
               "DMZ",
               "Internal",
               "Restricted",
               "Management",
               "Workstations"
             ]

      for host <- Graph.nodes(graph), host.type == Host do
        assert [{segment_id, %{type: Contains}}] =
                 graph
                 |> Graph.incoming(host.id)
                 |> Enum.filter(fn {_id, edge} -> edge.type == Contains end)

        assert %{type: NetworkSegment} = Graph.node(graph, segment_id)
      end

      internet = Enum.find(Graph.nodes(graph), &(&1.data.name == "internet"))

      assert [{segment_id, %{type: Contains}}] =
               graph
               |> Graph.incoming(internet.id)
               |> Enum.filter(fn {_id, edge} -> edge.type == Contains end)

      assert %{data: %{name: "External"}} = Graph.node(graph, segment_id)
    end

    test "shares each catalog CVE across matching services" do
      graph = EnterpriseTopology.generate(hosts: 20, seed: 1)

      vulnerability_nodes =
        graph
        |> Graph.nodes()
        |> Enum.filter(&(&1.type == Vulnerability))

      identifiers = Enum.map(vulnerability_nodes, & &1.data.identifier)

      assert MapSet.new(identifiers) ==
               MapSet.new(Enum.map(VulnerabilityCatalog.all(), & &1.identifier))

      assert length(identifiers) == MapSet.size(MapSet.new(identifiers))

      assert Enum.any?(vulnerability_nodes, fn vulnerability ->
               graph
               |> Graph.incoming(vulnerability.id)
               |> Enum.count(fn {_service_id, edge} -> edge.type == HasVulnerability end) > 1
             end)
    end

    test "emits segment policies only and follows the deny-default rules after materialization" do
      graph = EnterpriseTopology.generate(hosts: 10, seed: 7)

      assert Enum.count(Graph.edges(graph), &(&1.type == SegmentReachability)) == 8
      refute Enum.any?(Graph.edges(graph), &(&1.type == NetworkReachability))

      graph = MaterializeReachability.materialize(graph)

      reachability =
        graph
        |> Graph.edges()
        |> Enum.filter(&(&1.type == NetworkReachability))
        |> Enum.map(fn edge ->
          {Graph.node(graph, edge.from_id).data.name, Graph.node(graph, edge.to_id).data.name}
        end)

      assert {"internet", "https"} in reachability
      refute {"internet", "ssh"} in reachability
      assert Enum.any?(reachability, &match?({"dmz-web-" <> _, "api"}, &1))
      assert Enum.any?(reachability, &match?({"internal-api-" <> _, "postgresql"}, &1))
      assert Enum.any?(reachability, &match?({"internal-app-" <> _, "postgresql"}, &1))
      assert Enum.any?(reachability, &match?({"workstation-" <> _, "ldap"}, &1))
      assert Enum.any?(reachability, &match?({"workstation-" <> _, "smb"}, &1))
      assert Enum.any?(reachability, &match?({"mgmt-bastion-" <> _, "ssh"}, &1))

      assert Enum.all?(reachability, fn
               {"internet", to} -> to == "https"
               _ -> true
             end)
    end

    test "rejects a host count below the minimum" do
      assert_raise ArgumentError, fn ->
        EnterpriseTopology.generate(hosts: EnterpriseTopology.minimum_hosts() - 1, seed: 1)
      end
    end

    test "rejects an invalid title" do
      assert_raise ArgumentError, fn ->
        EnterpriseTopology.generate(title: "", hosts: EnterpriseTopology.minimum_hosts(), seed: 1)
      end
    end
  end

  describe "persistence" do
    test "persists a generated canonical policy topology" do
      graph = EnterpriseTopology.generate(title: "persisted", hosts: 8, seed: 3)

      assert graph.title == "persisted"
      assert Enum.count_until(host_names(graph), 10) == 9
      assert Graph.edges(graph) != []

      assert {:ok, %Graph{revision_number: 1}} = Graphs.insert(graph)
    end

    test "persists an enterprise-scale canonical topology" do
      graph = EnterpriseTopology.generate(title: "enterprise-scale", hosts: 249, seed: 69)

      assert {:ok, %Graph{revision_number: 1}} = Graphs.insert(graph)
    end
  end

  defp host_names(graph) do
    graph
    |> Graph.nodes()
    |> Enum.filter(&(&1.type == NetworkDefense.Nodes.Host))
    |> Enum.map(& &1.data.name)
  end
end
