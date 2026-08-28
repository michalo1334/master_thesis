defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ManifestSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :id, :string
    field :manifest_id, :string
    field :title, :string
    field :content, :map
  end

  @type t :: %__MODULE__{
          id: String.t(),
          manifest_id: String.t(),
          title: String.t(),
          content: map() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :manifest_id, :title, :content])
    |> validate_required([:id, :manifest_id, :title])
  end
end
