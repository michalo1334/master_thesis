defmodule NetworkDefenseWeb.Web.Contracts.SaveManifestPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :manifest_id, :string
    field :title, :string
    field :content, :map
  end

  @type t :: %__MODULE__{
          manifest_id: String.t(),
          title: String.t(),
          content: map()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:manifest_id, :title, :content])
    |> validate_required([:manifest_id, :title, :content])
    |> validate_length(:manifest_id, min: 1, max: 255)
    |> validate_length(:title, min: 1, max: 255)
  end
end
