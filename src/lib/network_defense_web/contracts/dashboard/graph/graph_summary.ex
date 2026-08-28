defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :graph_id, :string
    field :folder_id, :string
    field :title, :string
    field :revision_id, :string
    field :parent_revision_id, :string
    field :revision_number, :integer
    field :revision_kind, :string
    field :node_count, :integer
    field :edge_count, :integer
    field :is_favorite, :boolean
  end

  @type t :: %__MODULE__{
          graph_id: String.t(),
          folder_id: String.t() | nil,
          title: String.t(),
          revision_id: String.t(),
          parent_revision_id: String.t() | nil,
          revision_number: pos_integer(),
          revision_kind: String.t(),
          node_count: non_neg_integer(),
          edge_count: non_neg_integer(),
          is_favorite: boolean()
        }

  def from_domain(summary) do
    validate(%{
      graph_id: summary.graphId,
      folder_id: summary.folderId,
      title: summary.title,
      revision_id: summary.revisionId,
      parent_revision_id: summary.parentRevisionId,
      revision_number: summary.revisionNumber,
      revision_kind: summary.revisionKind,
      node_count: summary.nodeCount,
      edge_count: summary.edgeCount,
      is_favorite: summary.isFavorite
    })
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :graph_id,
      :folder_id,
      :title,
      :revision_id,
      :parent_revision_id,
      :revision_number,
      :revision_kind,
      :node_count,
      :edge_count,
      :is_favorite
    ])
    |> validate_required([
      :graph_id,
      :title,
      :revision_id,
      :revision_number,
      :revision_kind,
      :node_count,
      :edge_count,
      :is_favorite
    ])
    |> Contracts.validate_uuid(:graph_id)
    |> Contracts.validate_uuid(:folder_id)
    |> Contracts.validate_uuid(:revision_id)
    |> Contracts.validate_uuid(:parent_revision_id)
    |> validate_number(:node_count, greater_than_or_equal_to: 0)
    |> validate_number(:edge_count, greater_than_or_equal_to: 0)
  end
end
