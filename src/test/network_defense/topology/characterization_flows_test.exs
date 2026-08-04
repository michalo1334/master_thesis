defmodule NetworkDefense.Topology.CharacterizationFlowsTest do
  use NetworkDefense.DataCase

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Relationships.{NetworkReachability, SegmentReachability}
  alias NetworkDefense.Topology.EnterpriseTopology

  @hosts 8
  @seed 7

  describe "effective flows for hosts: 8, seed: 7" do
    test "pins the exact effective flow set" do
      graph = EnterpriseTopology.generate(hosts: @hosts, seed: @seed)

      assert policies(graph) ==
               MapSet.new([
                 {"External", "DMZ", :tcp, 443},
                 {"DMZ", "Internal", :tcp, 8080},
                 {"Internal", "Restricted", :tcp, 5432},
                 {"Workstations", "Restricted", :tcp, 389},
                 {"Workstations", "Restricted", :tcp, 445},
                 {"Management", "DMZ", :tcp, 22},
                 {"Management", "Internal", :tcp, 22},
                 {"Management", "Restricted", :tcp, 22}
               ])

      refute Enum.any?(Graph.edges(graph), &(&1.type == NetworkReachability))

      graph = MaterializeReachability.materialize(graph)

      assert Enum.count(reachability_edges(graph)) == 13

      assert flows(graph) ==
               MapSet.new([
                 {"internet", "https", :tcp, 443},
                 {"dmz-web-1", "api", :tcp, 8080},
                 {"internal-api-1", "postgresql", :tcp, 5432},
                 {"internal-app-1", "postgresql", :tcp, 5432},
                 {"internal-app-2", "postgresql", :tcp, 5432},
                 {"workstation-1", "ldap", :tcp, 389},
                 {"workstation-1", "smb", :tcp, 445},
                 {"mgmt-bastion-1", "ssh", :tcp, 22}
               ])
    end

    test "grants ingress, inter-segment, management, and workstation access" do
      graph = EnterpriseTopology.generate(hosts: @hosts, seed: @seed)
      graph = MaterializeReachability.materialize(graph)
      flows = flows(graph)

      assert {"internet", "https", :tcp, 443} in flows
      assert {"dmz-web-1", "api", :tcp, 8080} in flows
      assert {"internal-api-1", "postgresql", :tcp, 5432} in flows
      assert {"internal-app-1", "postgresql", :tcp, 5432} in flows
      assert {"mgmt-bastion-1", "ssh", :tcp, 22} in flows
      assert {"workstation-1", "ldap", :tcp, 389} in flows
      assert {"workstation-1", "smb", :tcp, 445} in flows
    end

    test "denies ingress, cross-tier, and same-segment access" do
      graph = EnterpriseTopology.generate(hosts: @hosts, seed: @seed)
      graph = MaterializeReachability.materialize(graph)
      flows = flows(graph)

      refute {"internet", "ssh", :tcp, 22} in flows
      refute {"workstation-1", "postgresql", :tcp, 5432} in flows
      refute {"dmz-web-1", "ssh", :tcp, 22} in flows
      refute {"internal-app-1", "api", :tcp, 8080} in flows
      refute {"internal-api-1", "app", :tcp, 8081} in flows
    end
  end

  defp policies(graph) do
    graph
    |> Graph.edges()
    |> Enum.filter(&(&1.type == SegmentReachability))
    |> Enum.map(fn edge ->
      source = Graph.node(graph, edge.from_id)
      target = Graph.node(graph, edge.to_id)
      {source.data.name, target.data.name, edge.data.protocol, edge.data.port_start}
    end)
    |> MapSet.new()
  end

  defp reachability_edges(graph) do
    Enum.filter(Graph.edges(graph), &(&1.type == NetworkReachability))
  end

  defp flows(graph) do
    graph
    |> reachability_edges()
    |> Enum.map(fn edge ->
      source = Graph.node(graph, edge.from_id)
      target = Graph.node(graph, edge.to_id)
      {source.data.name, target.data.name, target.data.protocol, target.data.port}
    end)
    |> MapSet.new()
  end
end
