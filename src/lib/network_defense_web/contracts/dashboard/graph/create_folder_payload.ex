defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.CreateFolderPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :name, :string
  end

  @type t :: %__MODULE__{name: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
