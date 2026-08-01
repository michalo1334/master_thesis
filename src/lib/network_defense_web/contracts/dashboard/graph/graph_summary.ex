defmodule NetworkDefenseWeb.Web.Contracts.GraphSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :graph_id, :string
    field :title, :string
    field :revision_id, :string
    field :parent_revision_id, :string
    field :revision_number, :integer
    field :revision_kind, :string
    field :node_count, :integer
    field :edge_count, :integer
  end

  @type t :: %__MODULE__{
          graph_id: String.t(),
          title: String.t(),
          revision_id: String.t(),
          parent_revision_id: String.t() | nil,
          revision_number: pos_integer(),
          revision_kind: String.t(),
          node_count: non_neg_integer(),
          edge_count: non_neg_integer()
        }

  def from_domain(summary) do
    validate(%{
      graph_id: summary.graphId,
      title: summary.title,
      revision_id: summary.revisionId,
      parent_revision_id: summary.parentRevisionId,
      revision_number: summary.revisionNumber,
      revision_kind: summary.revisionKind,
      node_count: summary.nodeCount,
      edge_count: summary.edgeCount
    })
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :graph_id,
      :title,
      :revision_id,
      :parent_revision_id,
      :revision_number,
      :revision_kind,
      :node_count,
      :edge_count
    ])
    |> validate_required([
      :graph_id,
      :title,
      :revision_id,
      :revision_number,
      :revision_kind,
      :node_count,
      :edge_count
    ])
    |> Contracts.validate_uuid(:graph_id)
    |> Contracts.validate_uuid(:revision_id)
    |> Contracts.validate_uuid(:parent_revision_id)
    |> validate_number(:node_count, greater_than_or_equal_to: 0)
    |> validate_number(:edge_count, greater_than_or_equal_to: 0)
  end
end
