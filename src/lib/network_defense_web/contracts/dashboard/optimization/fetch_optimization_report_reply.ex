defmodule NetworkDefenseWeb.Web.Contracts.FetchOptimizationReportReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  alias NetworkDefense.Optimization.OptimizationReport

  embedded_schema do
    field :optimization_id, :string
    field :graph_id, :string
    field :graph_title, :string
    field :graph_revision_id, :string

    embeds_one :report, NetworkDefenseWeb.Web.Contracts.OptimizationReport, on_replace: :update
  end

  @type t :: %__MODULE__{
          optimization_id: String.t(),
          graph_id: String.t(),
          graph_title: String.t(),
          graph_revision_id: String.t(),
          report: NetworkDefenseWeb.Web.Contracts.OptimizationReport.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:optimization_id, :graph_id, :graph_title, :graph_revision_id])
    |> cast_embed(:report, required: true)
    |> validate_required([:optimization_id, :graph_id, :graph_title, :graph_revision_id])
  end

  @spec from_domain(OptimizationReport.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def from_domain(%OptimizationReport{} = report) do
    %{
      optimization_id: report.optimization_id,
      graph_id: report.graph_id,
      graph_title: report.graph_title,
      graph_revision_id: report.graph_revision_id,
      report:
        Map.take(report, [
          :strategy,
          :objective,
          :requested_budget,
          :used_budget,
          :runtime_ms,
          :actions
        ])
    }
    |> validate()
  end
end
