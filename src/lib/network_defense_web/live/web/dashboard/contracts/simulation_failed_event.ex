defmodule NetworkDefenseWeb.Web.Contracts.SimulationFailedEvent do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  embedded_schema do
    field :correlation_id, :string
    field :graph_id, :string
    field :reason, :string
  end

  @type t :: %__MODULE__{
          correlation_id: String.t(),
          graph_id: String.t(),
          reason: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:correlation_id, :graph_id, :reason])
    |> validate_required([:correlation_id, :graph_id, :reason])
  end
end
