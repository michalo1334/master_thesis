defmodule NetworkDefenseWeb.Web.Contracts.CompareGraphsPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :base_revision_id, :string
    field :comparison_revision_id, :string
  end

  @type t :: %__MODULE__{
          base_revision_id: String.t(),
          comparison_revision_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:base_revision_id, :comparison_revision_id])
    |> validate_required([:base_revision_id, :comparison_revision_id])
    |> validate_length(:base_revision_id, min: 1)
    |> validate_length(:comparison_revision_id, min: 1)
    |> Contracts.validate_uuid(:base_revision_id)
    |> Contracts.validate_uuid(:comparison_revision_id)
  end
end
