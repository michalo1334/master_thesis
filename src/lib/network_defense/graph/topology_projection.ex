defmodule NetworkDefense.Graph.TopologyProjection do
  @moduledoc """
  Projects a structurally valid graph into the normalized topology read model.

  The projector owns segment membership, service ownership, context anchors,
  segment policy groups, and operational flow groups. The read model contains
  IDs, counts, and semantic relationships only. Names, data fields, positions,
  and display text stay in the editable graph.

  `project/1` is total for structurally valid graphs. Missing or ambiguous
  semantic relationships produce typed issues instead of errors. Ownership is
  never guessed: an entity without exactly one owner stays unplaced and is
  reported in `issues`.

  Every array and nested ID list is sorted, so identical graphs always
  produce identical projections.
  """

  alias NetworkDefense.Graph.{Graph, MaterializeReachability}

  alias NetworkDefense.Nodes.{
    Credential,
    Host,
    MissionCapability,
    NetworkSegment,
    Service,
    Vulnerability
  }

  alias NetworkDefense.Relationships.{
    AuthenticatesTo,
    Contains,
    HasVulnerability,
    Runs,
    SegmentReachability,
    StoresCredential,
    Supports
  }

  @type relationship_type ::
          :has_vulnerability
          | :stores_credential
          | :authenticates_to
          | :supports

  @type attachment_kind :: :vulnerability | :credential | :mission_capability

  @type issue_code ::
          :host_without_segment
          | :host_multiple_segments
          | :service_without_host
          | :service_multiple_hosts
          | :context_without_anchor

  @type severity :: :info | :warning

  @type anchor :: %{
          node_id: Ecto.UUID.t(),
          edge_id: Ecto.UUID.t(),
          relationship_type: relationship_type()
        }

  @type attachment :: %{
          id: Ecto.UUID.t(),
          kind: attachment_kind(),
          anchors: [anchor()]
        }

  @type segment :: %{
          id: Ecto.UUID.t(),
          host_ids: [Ecto.UUID.t()],
          host_count: non_neg_integer(),
          service_count: non_neg_integer(),
          context_count: non_neg_integer()
        }

  @type host :: %{
          id: Ecto.UUID.t(),
          segment_id: Ecto.UUID.t() | nil,
          service_ids: [Ecto.UUID.t()],
          service_count: non_neg_integer(),
          context_count: non_neg_integer()
        }

  @type service :: %{
          id: Ecto.UUID.t(),
          host_id: Ecto.UUID.t() | nil
        }

  @type policy_group :: %{
          from_segment_id: Ecto.UUID.t(),
          to_segment_id: Ecto.UUID.t(),
          edge_ids: [Ecto.UUID.t()]
        }

  @type flow_group :: %{
          source_host_id: Ecto.UUID.t(),
          target_host_id: Ecto.UUID.t(),
          service_ids: [Ecto.UUID.t()],
          flow_ids: [Ecto.UUID.t()]
        }

  @type issue :: %{
          code: issue_code(),
          severity: severity(),
          entity_id: Ecto.UUID.t(),
          related_ids: [Ecto.UUID.t()]
        }

  @type t :: %__MODULE__{
          segments: [segment()],
          hosts: [host()],
          services: [service()],
          attachments: [attachment()],
          policy_groups: [policy_group()],
          flow_groups: [flow_group()],
          issues: [issue()]
        }

  @enforce_keys [
    :segments,
    :hosts,
    :services,
    :attachments,
    :policy_groups,
    :flow_groups,
    :issues
  ]

  defstruct @enforce_keys

  @doc """
  Projects `graph` into the topology read model.

  The input graph must be structurally valid (see `NetworkDefense.Graph.hydrate/4`).
  Semantic incompleteness is acceptable and is reported through `issues`.
  """

  @spec project(Graph.t()) :: t()
  def project(%Graph{} = graph) do
    nodes = Graph.nodes(graph)
    edges = Graph.edges(graph)

    segments = node_ids(nodes, NetworkSegment)
    hosts = node_ids(nodes, Host)
    services = node_ids(nodes, Service)
    attachment_kinds = attachment_kinds(nodes)

    segment_memberships = memberships_by_target(edges, Contains)
    service_ownerships = memberships_by_target(edges, Runs)
    unique_segment_of = only_single_owners(segment_memberships)
    unique_host_of = only_single_owners(service_ownerships)

    hosts_by_segment = placed_by(unique_segment_of, hosts)
    services_by_host = placed_by(unique_host_of, services)

    anchor_index = attachment_anchors(edges, attachment_kinds)
    anchor_hosts = anchor_host_index(nodes, anchor_index, unique_host_of)
    host_context_counts = context_counts_by_host(anchor_hosts)
    segment_context_counts = context_counts_by_segment(anchor_hosts, unique_segment_of)

    %__MODULE__{
      segments:
        Enum.map(segments, fn segment_id ->
          host_ids = Enum.sort(Map.get(hosts_by_segment, segment_id, []))

          %{
            id: segment_id,
            host_ids: host_ids,
            host_count: length(host_ids),
            service_count: service_count_for_hosts(host_ids, services_by_host),
            context_count: Map.get(segment_context_counts, segment_id, 0)
          }
        end)
        |> Enum.sort_by(& &1.id),
      hosts:
        Enum.map(hosts, fn host_id ->
          service_ids = Enum.sort(Map.get(services_by_host, host_id, []))

          %{
            id: host_id,
            segment_id: Map.get(unique_segment_of, host_id),
            service_ids: service_ids,
            service_count: length(service_ids),
            context_count: Map.get(host_context_counts, host_id, 0)
          }
        end)
        |> Enum.sort_by(& &1.id),
      services:
        Enum.map(services, fn service_id ->
          %{id: service_id, host_id: Map.get(unique_host_of, service_id)}
        end)
        |> Enum.sort_by(& &1.id),
      attachments:
        Enum.map(Map.keys(attachment_kinds), fn attachment_id ->
          anchors =
            anchor_index
            |> Map.get(attachment_id, [])
            |> Enum.sort_by(&{&1.node_id, &1.edge_id})

          %{
            id: attachment_id,
            kind: Map.fetch!(attachment_kinds, attachment_id),
            anchors: anchors
          }
        end)
        |> Enum.sort_by(& &1.id),
      policy_groups: policy_groups(edges),
      flow_groups: flow_groups(graph, unique_host_of),
      issues:
        Enum.sort_by(
          host_issues(hosts, segment_memberships) ++
            service_issues(services, service_ownerships) ++
            context_issues(attachment_kinds, anchor_index, anchor_hosts),
          &{&1.code, &1.entity_id, &1.related_ids}
        )
    }
  end

  defp node_ids(nodes, node_type) do
    nodes
    |> Enum.filter(&(&1.type == node_type))
    |> Enum.map(& &1.id)
  end

  defp attachment_kinds(nodes) do
    Enum.reduce(nodes, %{}, fn node, index ->
      case node.type do
        Vulnerability -> Map.put(index, node.id, :vulnerability)
        Credential -> Map.put(index, node.id, :credential)
        MissionCapability -> Map.put(index, node.id, :mission_capability)
        _ -> index
      end
    end)
  end

  defp memberships_by_target(edges, relationship_type) do
    edges
    |> Enum.filter(&(&1.type == relationship_type))
    |> Enum.group_by(& &1.to_id, & &1.from_id)
  end

  defp only_single_owners(memberships) do
    memberships
    |> Enum.map(fn {id, owners} ->
      case Enum.uniq(owners) do
        [owner] -> {id, owner}
        _ -> {id, nil}
      end
    end)
    |> Map.new()
  end

  defp placed_by(owner_of, entity_ids) do
    entity_ids
    |> Enum.map(&{owner_of[&1], &1})
    |> Enum.reject(fn {owner_id, _entity_id} -> is_nil(owner_id) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp service_count_for_hosts(host_ids, services_by_host) do
    host_ids
    |> Enum.map(fn host_id -> Map.get(services_by_host, host_id, []) end)
    |> Enum.map(&length/1)
    |> Enum.sum()
  end

  defp attachment_anchors(edges, attachment_kinds) do
    edges
    |> Enum.map(&attachment_anchor/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn {attachment_id, _anchor} ->
      Map.has_key?(attachment_kinds, attachment_id)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp attachment_anchor(%{type: HasVulnerability, to_id: id, from_id: node_id, id: edge_id}) do
    anchor(id, :has_vulnerability, node_id, edge_id)
  end

  defp attachment_anchor(%{type: StoresCredential, to_id: id, from_id: node_id, id: edge_id}) do
    anchor(id, :stores_credential, node_id, edge_id)
  end

  defp attachment_anchor(%{type: AuthenticatesTo, from_id: id, to_id: node_id, id: edge_id}) do
    anchor(id, :authenticates_to, node_id, edge_id)
  end

  defp attachment_anchor(%{type: Supports, to_id: id, from_id: node_id, id: edge_id}) do
    anchor(id, :supports, node_id, edge_id)
  end

  defp attachment_anchor(_edge) do
    nil
  end

  defp anchor(attachment_id, relationship_type, node_id, edge_id) do
    {attachment_id,
     %{
       node_id: node_id,
       edge_id: edge_id,
       relationship_type: relationship_type
     }}
  end

  defp anchor_host_index(nodes, anchor_index, unique_host_of) do
    node_types = Map.new(nodes, &{&1.id, &1.type})

    Map.new(anchor_index, fn {attachment_id, anchors} ->
      hosts =
        anchors
        |> Enum.map(fn anchor -> resolved_host(node_types, anchor.node_id, unique_host_of) end)
        |> Enum.reject(&is_nil/1)

      {attachment_id, MapSet.new(hosts)}
    end)
  end

  defp resolved_host(node_types, node_id, unique_host_of) do
    case Map.get(node_types, node_id) do
      Host -> node_id
      Service -> Map.get(unique_host_of, node_id)
      _ -> nil
    end
  end

  defp context_counts_by_host(anchor_hosts) do
    anchor_hosts
    |> Map.values()
    |> Enum.flat_map(&MapSet.to_list/1)
    |> Enum.frequencies()
  end

  defp context_counts_by_segment(anchor_hosts, unique_segment_of) do
    anchor_hosts
    |> Map.values()
    |> Enum.flat_map(fn hosts ->
      hosts
      |> Enum.map(&Map.get(unique_segment_of, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    end)
    |> Enum.frequencies()
  end

  defp policy_groups(edges) do
    edges
    |> Enum.filter(&(&1.type == SegmentReachability))
    |> Enum.group_by(fn edge -> {edge.from_id, edge.to_id} end, & &1.id)
    |> Enum.map(fn {{from_segment_id, to_segment_id}, edge_ids} ->
      %{
        from_segment_id: from_segment_id,
        to_segment_id: to_segment_id,
        edge_ids: Enum.sort(edge_ids)
      }
    end)
    |> Enum.sort_by(&{&1.from_segment_id, &1.to_segment_id})
  end

  defp flow_groups(graph, unique_host_of) do
    graph
    |> MaterializeReachability.materialize()
    |> MaterializeReachability.operational_flows()
    |> Enum.map(fn flow ->
      {flow.from_id, Map.get(unique_host_of, flow.to_id), flow.to_id, flow.id}
    end)
    |> Enum.reject(fn {_source_host_id, target_host_id, _service_id, _flow_id} ->
      is_nil(target_host_id)
    end)
    |> Enum.group_by(
      fn {source_host_id, target_host_id, _service_id, _flow_id} ->
        {source_host_id, target_host_id}
      end,
      fn {_source_host_id, _target_host_id, service_id, flow_id} -> {service_id, flow_id} end
    )
    |> Enum.map(fn {{source_host_id, target_host_id}, pairs} ->
      %{
        source_host_id: source_host_id,
        target_host_id: target_host_id,
        service_ids: pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort(),
        flow_ids: pairs |> Enum.map(&elem(&1, 1)) |> Enum.sort()
      }
    end)
    |> Enum.sort_by(&{&1.source_host_id, &1.target_host_id})
  end

  defp host_issues(host_ids, segment_memberships) do
    host_ids
    |> Enum.reject(&Map.has_key?(segment_memberships, &1))
    |> Enum.map(&issue(:host_without_segment, &1, []))
    |> Enum.concat(
      Enum.flat_map(segment_memberships, fn {host_id, segment_ids} ->
        segment_ids = Enum.uniq(segment_ids) |> Enum.sort()

        case segment_ids do
          [_segment_id] -> []
          ids -> [issue(:host_multiple_segments, host_id, ids)]
        end
      end)
    )
  end

  defp service_issues(service_ids, service_ownerships) do
    service_ids
    |> Enum.reject(&Map.has_key?(service_ownerships, &1))
    |> Enum.map(&issue(:service_without_host, &1, []))
    |> Enum.concat(
      Enum.flat_map(service_ownerships, fn {service_id, host_ids} ->
        host_ids = Enum.uniq(host_ids) |> Enum.sort()

        case host_ids do
          [_host_id] -> []
          ids -> [issue(:service_multiple_hosts, service_id, ids)]
        end
      end)
    )
  end

  defp context_issues(attachment_kinds, anchor_index, anchor_hosts) do
    Enum.flat_map(attachment_kinds, fn {attachment_id, _kind} ->
      hosts = Map.get(anchor_hosts, attachment_id, MapSet.new())

      if MapSet.size(hosts) == 0 do
        related_ids =
          anchor_index
          |> Map.get(attachment_id, [])
          |> Enum.map(& &1.node_id)
          |> Enum.uniq()
          |> Enum.sort()

        [issue(:context_without_anchor, attachment_id, related_ids)]
      else
        []
      end
    end)
  end

  defp issue(code, entity_id, related_ids) do
    %{code: code, severity: :warning, entity_id: entity_id, related_ids: related_ids}
  end
end
