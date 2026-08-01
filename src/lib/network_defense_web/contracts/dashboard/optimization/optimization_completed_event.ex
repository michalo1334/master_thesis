defmodule NetworkDefenseWeb.Web.Contracts.OptimizationCompletedEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    field :correlation_id, :string
    field :graph_id, :string
    field :graph_revision_id, :string
    embeds_one :report, NetworkDefenseWeb.Web.Contracts.OptimizationReport, on_replace: :update
  end

  @type t :: %__MODULE__{
          correlation_id: String.t(),
          graph_id: String.t(),
          graph_revision_id: String.t(),
          report: NetworkDefenseWeb.Web.Contracts.OptimizationReport.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:correlation_id, :graph_id, :graph_revision_id])
    |> cast_embed(:report, required: true)
    |> validate_required([:correlation_id, :graph_id, :graph_revision_id])
  end
end
