defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphProjectionHost do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

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
    |> Contracts.validate_uuid(:id)
  end
end
