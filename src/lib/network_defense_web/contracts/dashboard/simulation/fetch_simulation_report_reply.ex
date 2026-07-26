defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationReportReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  alias NetworkDefense.Simulation.Report

  embedded_schema do
    field :experiment_id, :string
    field :graph_id, :string
    field :graph_title, :string
    field :graph_version_at_sim, :integer
    field :run_count, :integer
    field :iteration_count, :integer
    field :total_runtime_ms, :integer
    embeds_many :kpis, NetworkDefenseWeb.Web.Contracts.KpiMetric, on_replace: :delete
    embeds_one :charts, NetworkDefenseWeb.Web.Contracts.ReportCharts, on_replace: :update
  end

  @type t :: %__MODULE__{
          experiment_id: String.t(),
          graph_id: String.t(),
          graph_title: String.t(),
          graph_version_at_sim: integer(),
          run_count: integer(),
          iteration_count: integer(),
          total_runtime_ms: integer(),
          kpis: [NetworkDefenseWeb.Web.Contracts.KpiMetric.t()],
          charts: NetworkDefenseWeb.Web.Contracts.ReportCharts.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :experiment_id,
      :graph_id,
      :graph_title,
      :graph_version_at_sim,
      :run_count,
      :iteration_count,
      :total_runtime_ms
    ])
    |> cast_embed(:kpis, required: true)
    |> cast_embed(:charts, required: true)
    |> validate_required([
      :experiment_id,
      :graph_id,
      :graph_title,
      :graph_version_at_sim,
      :run_count,
      :iteration_count,
      :total_runtime_ms
    ])
  end

  @spec from_domain(Report.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def from_domain(%Report{} = report) do
    report
    |> Contracts.to_wire()
    |> validate()
  end
end
