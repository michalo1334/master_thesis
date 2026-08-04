defmodule NetworkDefenseWeb.Web.Contracts.GraphProjectionOperationalFlow do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :id, :string
    field :from_id, :string
    field :to_id, :string
  end

  @type t :: %__MODULE__{
          id: String.t(),
          from_id: String.t(),
          to_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :from_id, :to_id])
    |> validate_required([:id, :from_id, :to_id])
    |> Contracts.validate_uuid(:id)
    |> Contracts.validate_uuid(:from_id)
    |> Contracts.validate_uuid(:to_id)
  end
end
