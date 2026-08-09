defmodule NetworkDefense.Graph.MaterializeReachability do
  @moduledoc """
  Projects a canonical segment-policy graph onto an in-memory operational graph.

  Resolves `Contains`, `Runs`, and `SegmentReachability` into directed
  `NetworkReachability` marker edges (`Host -> Service`). Policies are deny by
  default: a flow exists only when the source host's segment and the target
  host's segment are linked by a matching policy, and same-segment traffic
  requires an explicit self policy. Output is deterministic, deduplicated by
  {source host, target service}, sorted, and idempotent. Canonical nodes and
  edges are kept unchanged.
  """

  alias NetworkDefense.Graph.{Edge, Graph}
  alias NetworkDefense.Relationships.{Contains, NetworkReachability, Runs, SegmentReachability}

  @doc """
  Returns `graph` with the effective `NetworkReachability` marker edges added.

  Existing marker edges are removed first, so repeated materialization is
  idempotent.
  """
  def materialize(%Graph{} = graph) do
    graph
    |> strip_markers()
    |> add_markers(effective_flows(graph))
  end

  @doc """
  Serializes the `NetworkReachability` edges of a materialized graph as
  lightweight `%{id, from_id, to_id}` maps.
  """
  @spec operational_flows(Graph.t()) :: [map()]
  def operational_flows(%Graph{} = graph) do
    graph
    |> Graph.edges()
    |> Enum.filter(&(&1.type == NetworkReachability))
    |> Enum.map(&%{id: &1.id, from_id: &1.from_id, to_id: &1.to_id})
  end

  defp strip_markers(graph) do
    graph
    |> marker_edges()
    |> Enum.reduce(graph, fn edge, graph -> Graph.remove_edge_by_id(graph, edge.id) end)
  end

  defp add_markers(graph, flows) do
    Enum.reduce(flows, graph, fn edge, graph -> Graph.add_edge(graph, edge) end)
  end

  defp marker_edges(graph) do
    Enum.filter(Graph.edges(graph), &(&1.type == NetworkReachability))
  end

  defp effective_flows(graph) do
    graph
    |> flow_pairs()
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn {source_id, service_id} ->
      operational_edge(graph.id, source_id, service_id)
    end)
  end

  defp flow_pairs(graph) do
    hosts_by_segment = hosts_by_segment(graph)
    services_by_host = services_by_host(graph)

    for {source_segment, target_segment, policy} <- policies(graph),
        source_host <- Map.get(hosts_by_segment, source_segment, []),
        target_host <- Map.get(hosts_by_segment, target_segment, []),
        service_id <- Map.get(services_by_host, target_host, []),
        service = Graph.node(graph, service_id),
        matches?(policy, service) do
      {source_host, service_id}
    end
  end

  defp policies(graph) do
    Enum.flat_map(Graph.edges(graph), fn
      %{type: SegmentReachability, from_id: from_id, to_id: to_id, data: policy} ->
        [{from_id, to_id, policy}]

      _ ->
        []
    end)
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

  defp services_by_host(graph) do
    graph
    |> Graph.edges()
    |> Enum.flat_map(fn
      %{type: Runs, from_id: host_id, to_id: service_id} -> [{host_id, service_id}]
      _ -> []
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp matches?(policy, service) do
    protocol_matches?(policy.protocol, service.data.protocol) and
      port_matches?(policy, service.data.port)
  end

  defp protocol_matches?(:any, _protocol), do: true

  defp protocol_matches?(policy_protocol, service_protocol),
    do: policy_protocol == service_protocol

  defp port_matches?(%{port_start: nil}, _port), do: true

  defp port_matches?(%{port_start: port_start, port_end: port_end}, port),
    do: port_start <= port and port <= port_end

  defp operational_edge(graph_id, source_id, service_id) do
    %Edge{
      id: operational_id(graph_id, source_id, service_id),
      graph_id: graph_id,
      from_id: source_id,
      to_id: service_id,
      type: NetworkReachability,
      data: %NetworkReachability{}
    }
  end

  defp operational_id(graph_id, source_id, service_id) do
    digest = :crypto.hash(:sha256, graph_id <> source_id <> service_id)
    {:ok, uuid} = Ecto.UUID.cast(binary_part(digest, 0, 16))
    uuid
  end
end
