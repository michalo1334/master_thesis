defmodule NetworkDefenseWeb.Web.Contracts.SimulationCompletedEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :correlation_id, :string
    field :graph_id, :string
    field :graph_revision_id, :string
    field :experiment_id, :string
  end

  @type t :: %__MODULE__{
          correlation_id: String.t(),
          graph_id: String.t(),
          graph_revision_id: String.t(),
          experiment_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:correlation_id, :graph_id, :graph_revision_id, :experiment_id])
    |> validate_required([:correlation_id, :graph_id, :graph_revision_id, :experiment_id])
  end
end
