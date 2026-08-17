defmodule NetworkDefense.Topology.MissionCapabilitiesTest do
  use NetworkDefense.DataCase

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Nodes.{MissionCapability, NetworkSegment, Service}
  alias NetworkDefense.Relationships.SegmentReachability
  alias NetworkDefense.Simulation.MissionImpact
  alias NetworkDefense.Topology.EnterpriseTopology

  @hosts 8
  @seed 7

  describe "generated mission capabilities" do
    test "declares public and internal required flows against real segments and services" do
      graph = EnterpriseTopology.generate(hosts: @hosts, seed: @seed)

      capabilities = mission_capabilities(graph)
      assert [_, _] = capabilities

      assert Enum.map(capabilities, & &1.data.name) == ["Public web presence", "Order processing"]

      for capability <- capabilities do
        assert capability.data.required_flows != []

        for flow <- capability.data.required_flows do
          assert %{type: NetworkSegment} = Graph.node(graph, flow.source_segment_id)
          assert %{type: Service} = Graph.node(graph, flow.target_service_id)
        end
      end
    end

    test "links each capability to its supporting hosts" do
      graph = EnterpriseTopology.generate(hosts: @hosts, seed: @seed)

      for capability <- mission_capabilities(graph) do
        supports = Graph.supporting_host_ids(graph, capability.id)

        assert length(supports) >= capability.data.min_operational_support
        assert length(supports) == length(Enum.uniq(supports))
      end
    end

    test "is deterministic across generations" do
      first = EnterpriseTopology.generate(hosts: @hosts, seed: @seed)
      second = EnterpriseTopology.generate(hosts: @hosts, seed: @seed)

      assert capability_signature(first) == capability_signature(second)
    end
  end

  describe "mission feasibility" do
    test "baseline scenario is feasible pre-attack" do
      graph = EnterpriseTopology.generate(hosts: @hosts, seed: @seed)

      assert MissionImpact.pre_attack_feasible?(graph)
    end

    test "cutting the required ingress policy makes the scenario infeasible" do
      graph = EnterpriseTopology.generate(hosts: @hosts, seed: @seed)
      ingress = policy_edge(graph, "External", "DMZ")

      graph = Graph.remove_edge_by_id(graph, ingress.id)

      refute MissionImpact.pre_attack_feasible?(graph)

      assert [public] =
               MissionImpact.pre_attack_status(graph)
               |> Enum.filter(&(&1.name == "Public web presence"))

      assert public.down?
    end

    test "preserves at least one exposure that no capability requires" do
      graph = EnterpriseTopology.generate(hosts: @hosts, seed: @seed)

      graph =
        [{"Workstations", "Restricted"}, {"Management", "DMZ"}]
        |> Enum.reduce(graph, fn {from, to}, graph ->
          Graph.remove_edge_by_id(graph, policy_edge(graph, from, to).id)
        end)

      assert MissionImpact.pre_attack_feasible?(graph)
    end
  end

  defp mission_capabilities(graph) do
    graph
    |> Graph.nodes()
    |> Enum.filter(&(&1.type == MissionCapability))
  end

  defp policy_edge(graph, from_name, to_name) do
    graph
    |> Graph.edges()
    |> Enum.find(fn edge ->
      edge.type == SegmentReachability and
        Graph.node(graph, edge.from_id).data.name == from_name and
        Graph.node(graph, edge.to_id).data.name == to_name
    end)
  end

  defp capability_signature(graph) do
    graph
    |> mission_capabilities()
    |> Enum.map(fn capability ->
      {capability.data.name, capability.data.impact_weight,
       Enum.map(capability.data.required_flows, fn flow ->
         {Graph.node(graph, flow.source_segment_id).data.name,
          Graph.node(graph, flow.target_service_id).data.name}
       end)}
    end)
  end
end
