defmodule NetworkDefenseWeb.Web.Contracts.GraphContract do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  embedded_schema do
    field :id, :string
    field :title, :string
    field :lock_version, :integer
    embeds_many :nodes, NetworkDefenseWeb.Web.Contracts.Node, on_replace: :delete
    embeds_many :edges, NetworkDefenseWeb.Web.Contracts.Edge, on_replace: :delete
  end

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          nodes: [NetworkDefenseWeb.Web.Contracts.Node.t()],
          edges: [NetworkDefenseWeb.Web.Contracts.Edge.t()],
          lock_version: integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :title, :lock_version])
    |> cast_embed(:nodes)
    |> cast_embed(:edges)
    |> validate_required([:id, :title, :lock_version])
    |> validate_length(:title, min: 1)
  end
end
