defmodule NetworkDefense.Graph.Contracts.GraphContract do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.Graph.Contracts.{Edge, Node}

  embedded_schema do
    field :id, :string
    field :title, :string
    field :revision_id, :string
    field :parent_revision_id, :string
    field :revision_number, :integer
    field :revision_kind, :string
    embeds_many :nodes, Node, on_replace: :delete
    embeds_many :edges, Edge, on_replace: :delete
  end

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          nodes: [Node.t()],
          edges: [Edge.t()],
          revision_id: String.t() | nil,
          parent_revision_id: String.t() | nil,
          revision_number: integer() | nil,
          revision_kind: String.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :id,
      :title,
      :revision_id,
      :parent_revision_id,
      :revision_number,
      :revision_kind
    ])
    |> cast_embed(:nodes)
    |> cast_embed(:edges)
    |> validate_required([:id, :title])
    |> Contracts.validate_uuid(:id)
    |> Contracts.validate_uuid(:revision_id)
    |> Contracts.validate_uuid(:parent_revision_id)
    |> validate_length(:title, min: 1)
  end
end
