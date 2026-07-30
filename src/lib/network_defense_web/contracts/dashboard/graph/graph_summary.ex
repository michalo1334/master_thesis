defmodule NetworkDefenseWeb.Web.Contracts.GraphSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :id, :string
    field :title, :string
    field :parent_id, :string
    field :tags, {:array, :string}
    field :node_count, :integer
    field :edge_count, :integer
  end

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          parent_id: String.t() | nil,
          tags: [String.t()],
          node_count: non_neg_integer(),
          edge_count: non_neg_integer()
        }

  def from_domain(summary) do
    validate(%{
      id: summary.id,
      title: summary.title,
      parent_id: summary.parentId,
      tags: summary.tags,
      node_count: summary.nodeCount,
      edge_count: summary.edgeCount
    })
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :title, :parent_id, :tags, :node_count, :edge_count])
    |> validate_required([:id, :title, :tags, :node_count, :edge_count])
    |> Contracts.validate_uuid(:id)
    |> Contracts.validate_uuid(:parent_id)
    |> validate_number(:node_count, greater_than_or_equal_to: 0)
    |> validate_number(:edge_count, greater_than_or_equal_to: 0)
  end
end
