defmodule NetworkDefenseWeb.Web.Contracts.FolderSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :id, :string
    field :name, :string
  end

  @type t :: %__MODULE__{id: String.t(), name: String.t()}

  def from_domain(folder), do: validate(%{id: folder.id, name: folder.name})

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :name])
    |> validate_required([:id, :name])
    |> Contracts.validate_uuid(:id)
  end
end
