defmodule NetworkDefenseWeb.Web.Contracts.SetGraphRevisionFavoritePayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :graph_revision_id, :string
    field :favorite, :boolean
  end

  @type t :: %__MODULE__{
          graph_revision_id: String.t(),
          favorite: boolean()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_revision_id, :favorite])
    |> validate_required([:graph_revision_id, :favorite])
    |> Contracts.validate_uuid(:graph_revision_id)
  end
end
