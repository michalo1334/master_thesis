defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  alias NetworkDefense.Graph.TopologyProjection, as: DomainProjection
  alias NetworkDefense.Nodes.Registry, as: NodeRegistry
  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry

  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection.{
    Attachment,
    FlowGroup,
    Host,
    Issue,
    PolicyGroup,
    Segment,
    Service
  }

  embedded_schema do
    embeds_many :segments, Segment, on_replace: :delete
    embeds_many :hosts, Host, on_replace: :delete
    embeds_many :services, Service, on_replace: :delete
    embeds_many :attachments, Attachment, on_replace: :delete
    embeds_many :policy_groups, PolicyGroup, on_replace: :delete
    embeds_many :flow_groups, FlowGroup, on_replace: :delete
    embeds_many :issues, Issue, on_replace: :delete
  end

  @type t :: %__MODULE__{
          segments: [Segment.t()],
          hosts: [Host.t()],
          services: [Service.t()],
          attachments: [Attachment.t()],
          policy_groups: [PolicyGroup.t()],
          flow_groups: [FlowGroup.t()],
          issues: [Issue.t()]
        }

  @doc """
  Converts a domain topology projection into its wire contract.

  Node types and relationship types use the contract type names that the rest of
  the dashboard wire surface already uses ("Vulnerability", "StoresCredential").
  Issue codes and severities stay in their domain spelling.

  Returns the wire map, like `GraphContract.from_domain/1`, so callers can embed
  it directly into another contract.
  """
  @spec from_domain(DomainProjection.t()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def from_domain(%DomainProjection{} = projection) do
    with {:ok, contract} <-
           validate(%{
             segments: Enum.map(projection.segments, &segment_attrs/1),
             hosts: Enum.map(projection.hosts, &host_attrs/1),
             services: Enum.map(projection.services, &service_attrs/1),
             attachments: Enum.map(projection.attachments, &attachment_attrs/1),
             policy_groups: Enum.map(projection.policy_groups, &policy_group_attrs/1),
             flow_groups: Enum.map(projection.flow_groups, &flow_group_attrs/1),
             issues: Enum.map(projection.issues, &issue_attrs/1)
           }) do
      {:ok, to_wire(contract)}
    end
  end

  def changeset(schema, attrs) do
    # `cast_embed/2` requires a cast changeset; the root has no scalar fields.
    schema
    |> cast(attrs, [])
    |> cast_embed(:segments)
    |> cast_embed(:hosts)
    |> cast_embed(:services)
    |> cast_embed(:attachments)
    |> cast_embed(:policy_groups)
    |> cast_embed(:flow_groups)
    |> cast_embed(:issues)
  end

  defp segment_attrs(segment) do
    %{
      id: segment.id,
      host_ids: segment.host_ids,
      host_count: segment.host_count,
      service_count: segment.service_count,
      context_count: segment.context_count
    }
  end

  defp host_attrs(host) do
    %{
      id: host.id,
      segment_id: host.segment_id,
      service_ids: host.service_ids,
      service_count: host.service_count,
      context_count: host.context_count
    }
  end

  defp service_attrs(service) do
    %{id: service.id, host_id: service.host_id}
  end

  defp attachment_attrs(attachment) do
    %{
      id: attachment.id,
      node_type: NodeRegistry.contract_type_for_short(attachment.kind),
      anchors: Enum.map(attachment.anchors, &anchor_attrs/1)
    }
  end

  defp anchor_attrs(anchor) do
    %{
      node_id: anchor.node_id,
      edge_id: anchor.edge_id,
      relationship_type:
        RelationshipRegistry.contract_type_for_canonical_short(anchor.relationship_type)
    }
  end

  defp policy_group_attrs(group) do
    %{
      from_segment_id: group.from_segment_id,
      to_segment_id: group.to_segment_id,
      edge_ids: group.edge_ids
    }
  end

  defp flow_group_attrs(group) do
    %{
      source_host_id: group.source_host_id,
      target_host_id: group.target_host_id,
      service_ids: group.service_ids,
      flow_ids: group.flow_ids
    }
  end

  defp issue_attrs(issue) do
    %{
      code: to_string(issue.code),
      severity: to_string(issue.severity),
      entity_id: issue.entity_id,
      related_ids: issue.related_ids
    }
  end
end
