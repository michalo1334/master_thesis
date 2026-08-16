defmodule NetworkDefenseWeb.Web.Contracts.DocumentCatalogGraphFilterOption do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workspace

  embedded_schema do
    field :id, :string
    field :title, :string
  end

  @type t :: %__MODULE__{id: String.t(), title: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :title])
    |> validate_required([:id, :title])
    |> NetworkDefense.Contracts.validate_uuid(:id)
  end
end
