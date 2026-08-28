defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.MoveGraphToFolderPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :graph_id, :string
    field :folder_id, :string
  end

  @type t :: %__MODULE__{graph_id: String.t(), folder_id: String.t() | nil}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_id, :folder_id])
    |> validate_required([:graph_id])
    |> Contracts.validate_uuid(:graph_id)
    |> Contracts.validate_uuid(:folder_id)
  end
end
