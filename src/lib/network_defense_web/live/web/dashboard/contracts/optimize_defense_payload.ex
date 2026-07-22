defmodule NetworkDefenseWeb.Web.Contracts.OptimizeDefensePayload do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  embedded_schema do
    field :graph_id, :string
  end

  @type t :: %__MODULE__{graph_id: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_id])
    |> validate_required([:graph_id])
    |> validate_length(:graph_id, min: 1)
  end
end
