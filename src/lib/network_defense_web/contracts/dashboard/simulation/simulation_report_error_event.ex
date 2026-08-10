defmodule NetworkDefenseWeb.Web.Contracts.SimulationReportErrorEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  alias NetworkDefenseWeb.Web.Contracts.DashboardError

  embedded_schema do
    field :experiment_id, :string
    field :graph_revision_id, :string
    embeds_one :error, DashboardError, on_replace: :update
  end

  @type t :: %__MODULE__{
          experiment_id: String.t(),
          graph_revision_id: String.t(),
          error: DashboardError.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:experiment_id, :graph_revision_id])
    |> cast_embed(:error, required: true)
    |> validate_required([:experiment_id, :graph_revision_id])
  end
end
