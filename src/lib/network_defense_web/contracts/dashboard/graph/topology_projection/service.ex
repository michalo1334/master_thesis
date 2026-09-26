defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection.Service do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :id, :string
    field :host_id, :string
  end

  @type t :: %__MODULE__{
          id: String.t(),
          host_id: String.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :host_id])
    |> validate_required([:id])
    |> Contracts.validate_uuid(:id)
    |> Contracts.validate_uuid(:host_id)
  end
end
