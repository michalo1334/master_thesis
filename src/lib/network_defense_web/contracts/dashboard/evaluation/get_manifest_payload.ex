defmodule NetworkDefenseWeb.Web.Contracts.GetManifestPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :id, :string
  end

  @type t :: %__MODULE__{
          id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id])
    |> validate_required([:id])
  end
end
