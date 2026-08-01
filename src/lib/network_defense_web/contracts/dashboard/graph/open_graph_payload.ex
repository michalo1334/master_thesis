defmodule NetworkDefenseWeb.Web.Contracts.OpenGraphPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :graph_revision_id, :string
  end

  @type t :: %__MODULE__{
          graph_revision_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_revision_id])
    |> validate_required([:graph_revision_id])
    |> Contracts.validate_uuid(:graph_revision_id)
  end
end
