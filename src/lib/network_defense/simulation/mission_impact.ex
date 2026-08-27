defmodule NetworkDefense.Simulation.MissionImpact do
  @moduledoc false

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Nodes.MissionCapability
  alias NetworkDefense.Relationships.{Contains, NetworkReachability, Runs}

  @spec final(Graph.t(), [String.t()]) :: float()
  def final(graph, foothold_ids) do
    graph
    |> capability_statuses(foothold_ids)
    |> Enum.reduce(0.0, fn capability, impact ->
      if capability.down?, do: impact + capability.impact_weight, else: impact
    end)
  end

  @spec pre_attack_status(Graph.t()) :: [map()]
  def pre_attack_status(graph), do: capability_statuses(graph, [])

  @spec required_flow_statuses(Graph.t()) :: [map()]
  def required_flow_statuses(graph) do
    materialized = MaterializeReachability.materialize(graph)
    flows = operational_flows(materialized)
    hosts_by_segment = hosts_by_segment(graph)

    graph
    |> Graph.nodes()
    |> Enum.filter(&(&1.type == MissionCapability))
    |> Enum.flat_map(fn capability ->
      Enum.map(capability.data.required_flows, fn flow ->
        %{
          capability_id: capability.id,
          capability_name: capability.data.name,
          source_segment_id: flow.source_segment_id,
          target_service_id: flow.target_service_id,
          available?: flow_exists?(flows, hosts_by_segment, flow)
        }
      end)
    end)
  end

  @spec pre_attack_feasible?(Graph.t()) :: boolean()
  def pre_attack_feasible?(graph) do
    graph
    |> pre_attack_status()
    |> Enum.all?(&(!&1.down?))
  end

  @spec capability_statuses(Graph.t(), [String.t()]) :: [map()]
  def capability_statuses(graph, foothold_ids) do
    capabilities =
      graph
      |> Graph.nodes()
      |> Enum.filter(&(&1.type == MissionCapability))

    if capabilities == [] do
      []
    else
      statuses(capabilities, graph, MapSet.new(foothold_ids))
    end
  end

  defp statuses(capabilities, graph, compromised) do
    materialized = MaterializeReachability.materialize(graph)
    flows = operational_flows(materialized)
    hosts_by_segment = hosts_by_segment(graph)
    host_by_service = host_by_service(graph)

    Enum.map(capabilities, fn capability ->
      supporting_host_ids = Graph.supporting_host_ids(graph, capability.id)

      compromised_support_count =
        Enum.count(supporting_host_ids, &MapSet.member?(compromised, &1))

      supporting_host_count = length(supporting_host_ids)

      required_flows = capability.data.required_flows

      missing_flow_count =
        Enum.count(required_flows, &(not flow_exists?(flows, hosts_by_segment, &1)))

      compromised_target_host_count =
        required_flows
        |> Enum.map(&target_host(&1, host_by_service))
        |> Enum.uniq()
        |> Enum.count(&MapSet.member?(compromised, &1))

      support_ok? =
        supporting_host_count - compromised_support_count >=
          capability.data.min_operational_support

      %{
        capability_id: capability.id,
        name: capability.data.name,
        impact_weight: capability.data.impact_weight,
        supporting_host_count: supporting_host_count,
        compromised_support_count: compromised_support_count,
        required_flow_count: length(required_flows),
        missing_flow_count: missing_flow_count,
        min_operational_support: capability.data.min_operational_support,
        compromised_target_host_count: compromised_target_host_count,
        down?: missing_flow_count > 0 or compromised_target_host_count > 0 or not support_ok?
      }
    end)
  end

  defp flow_exists?(flows, hosts_by_segment, flow) do
    source_hosts = Map.get(hosts_by_segment, flow.source_segment_id, [])

    Enum.any?(flows, fn {from_id, to_id} ->
      to_id == flow.target_service_id and from_id in source_hosts
    end)
  end

  defp target_host(flow, host_by_service), do: Map.get(host_by_service, flow.target_service_id)

  defp operational_flows(graph) do
    graph
    |> Graph.edges()
    |> Enum.filter(&(&1.type == NetworkReachability))
    |> Enum.map(&{&1.from_id, &1.to_id})
  end

  defp hosts_by_segment(graph) do
    graph
    |> Graph.edges()
    |> Enum.flat_map(fn
      %{type: Contains, from_id: segment_id, to_id: host_id} -> [{segment_id, host_id}]
      _ -> []
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp host_by_service(graph) do
    graph
    |> Graph.edges()
    |> Enum.reduce(%{}, fn
      %{type: Runs, from_id: host_id, to_id: service_id}, acc ->
        Map.put(acc, service_id, host_id)

      _, acc ->
        acc
    end)
  end
end
