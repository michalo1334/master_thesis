defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationReportReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  alias NetworkDefense.Simulation.SimulationReport
  alias NetworkDefense.Graph.Contracts.GraphContract

  embedded_schema do
    field :experiment_id, :string
    field :graph_id, :string
    field :graph_title, :string
    field :graph_version_at_sim, :integer
    field :run_count, :integer
    field :iteration_count, :integer
    field :total_runtime_ms, :integer

    embeds_one :graph, NetworkDefense.Graph.Contracts.GraphContract, on_replace: :update

    embeds_one :summary, NetworkDefenseWeb.Web.Contracts.SimulationReportSummary,
      on_replace: :update

    embeds_one :charts, NetworkDefenseWeb.Web.Contracts.SimulationReportCharts,
      on_replace: :update
  end

  @type t :: %__MODULE__{
          experiment_id: String.t(),
          graph_id: String.t(),
          graph_title: String.t(),
          graph_version_at_sim: integer(),
          run_count: integer(),
          iteration_count: integer(),
          total_runtime_ms: integer(),
          graph: NetworkDefense.Graph.Contracts.GraphContract.t(),
          summary: NetworkDefenseWeb.Web.Contracts.SimulationReportSummary.t(),
          charts: NetworkDefenseWeb.Web.Contracts.SimulationReportCharts.t()
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
    |> cast_embed(:graph, required: true)
    |> cast_embed(:summary, required: true)
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

  @spec from_domain(SimulationReport.t(), NetworkDefense.Graph.Graph.t()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def from_domain(%SimulationReport{} = report, graph) do
    with {:ok, wire_graph} <- GraphContract.from_domain(graph) do
      report
      |> Contracts.to_wire()
      |> Map.put(:graph, wire_graph)
      |> validate()
    end
  end
end
