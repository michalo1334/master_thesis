defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.DeleteFolderPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :folder_id, :string
  end

  @type t :: %__MODULE__{folder_id: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:folder_id])
    |> validate_required([:folder_id])
    |> Contracts.validate_uuid(:folder_id)
  end
end
