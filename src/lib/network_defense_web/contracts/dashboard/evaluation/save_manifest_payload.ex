defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.SaveManifestPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :manifest_id, :string
    field :existing_manifest_id, :string
    field :title, :string
    field :content, :map
  end

  @type t :: %__MODULE__{
          manifest_id: String.t(),
          existing_manifest_id: String.t() | nil,
          title: String.t(),
          content: map()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:manifest_id, :existing_manifest_id, :title, :content])
    |> validate_required([:manifest_id, :title, :content])
    |> validate_length(:manifest_id, min: 1, max: 255)
    |> Contracts.validate_uuid(:existing_manifest_id)
    |> validate_length(:title, min: 1, max: 255)
  end
end
