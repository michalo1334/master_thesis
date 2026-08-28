defmodule NetworkDefenseWeb.Contracts.Dashboard.Optimization.OptimizationReportErrorEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  alias NetworkDefenseWeb.Contracts.Dashboard.DashboardError

  embedded_schema do
    field :document_id, :string
    field :optimization_id, :string
    embeds_one :error, DashboardError, on_replace: :update
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          optimization_id: String.t(),
          error: DashboardError.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :optimization_id])
    |> cast_embed(:error, required: true)
    |> validate_required([:document_id, :optimization_id])
    |> Contracts.validate_uuid(:document_id)
  end
end
