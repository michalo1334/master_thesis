defmodule NetworkDefenseWeb.Web.Contracts.OptimizationReportErrorEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  alias NetworkDefenseWeb.Web.Contracts.DashboardError

  embedded_schema do
    field :document_id, :string
    field :optimization_id, :string
    field :graph_revision_id, :string
    embeds_one :error, DashboardError, on_replace: :update
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          optimization_id: String.t(),
          graph_revision_id: String.t(),
          error: DashboardError.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :optimization_id, :graph_revision_id])
    |> cast_embed(:error, required: true)
    |> validate_required([:document_id, :optimization_id, :graph_revision_id])
    |> Contracts.validate_uuid(:document_id)
  end
end
