defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationReportReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  alias NetworkDefense.Simulation.SimulationReport
  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefenseWeb.Web.Contracts.GraphProjectionOperationalFlow

  embedded_schema do
    field(:experiment_id, :string)
    field(:graph_id, :string)
    field(:graph_title, :string)
    field(:graph_revision_id, :string)
    field(:run_count, :integer)
    field(:iteration_count, :integer)
    field(:total_runtime_ms, :integer)
    field(:feasible, :boolean)

    embeds_one(:graph, NetworkDefense.Graph.Contracts.GraphContract, on_replace: :update)

    embeds_many(:operational_flows, GraphProjectionOperationalFlow, on_replace: :delete)

    embeds_many(
      :capability_statuses,
      NetworkDefenseWeb.Web.Contracts.SimulationReportCapabilityStatus,
      on_replace: :delete
    )

    embeds_one(:summary, NetworkDefenseWeb.Web.Contracts.SimulationReportSummary,
      on_replace: :update
    )

    embeds_one(:charts, NetworkDefenseWeb.Web.Contracts.SimulationReportCharts,
      on_replace: :update
    )
  end

  @type t :: %__MODULE__{
          experiment_id: String.t(),
          graph_id: String.t(),
          graph_title: String.t(),
          graph_revision_id: String.t(),
          run_count: integer(),
          iteration_count: integer(),
          total_runtime_ms: integer(),
          feasible: boolean(),
          graph: NetworkDefense.Graph.Contracts.GraphContract.t(),
          operational_flows: [GraphProjectionOperationalFlow.t()],
          capability_statuses: [
            NetworkDefenseWeb.Web.Contracts.SimulationReportCapabilityStatus.t()
          ],
          summary: NetworkDefenseWeb.Web.Contracts.SimulationReportSummary.t(),
          charts: NetworkDefenseWeb.Web.Contracts.SimulationReportCharts.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :experiment_id,
      :graph_id,
      :graph_title,
      :graph_revision_id,
      :run_count,
      :iteration_count,
      :total_runtime_ms,
      :feasible
    ])
    |> cast_embed(:graph, required: true)
    |> cast_embed(:operational_flows)
    |> cast_embed(:capability_statuses)
    |> cast_embed(:summary, required: true)
    |> cast_embed(:charts, required: true)
    |> validate_required([
      :experiment_id,
      :graph_id,
      :graph_title,
      :graph_revision_id,
      :run_count,
      :iteration_count,
      :total_runtime_ms,
      :feasible
    ])
  end

  @spec from_domain(SimulationReport.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def from_domain(%SimulationReport{} = report) do
    with {:ok, wire_graph} <- GraphContract.from_domain(report.graph) do
      report
      |> Contracts.to_wire()
      |> Map.put(:graph, wire_graph)
      |> Map.put(:feasible, report.pre_attack_feasible)
      |> Map.put(:capability_statuses, capability_statuses(report))
      |> validate()
    end
  end

  defp capability_statuses(report) do
    Enum.map(report.pre_attack_capability_statuses, fn status ->
      %{
        capability_id: status.capability_id,
        operational: !status.down?,
        required_flow_count: status.required_flow_count,
        missing_flow_count: status.missing_flow_count,
        supporting_host_count: status.supporting_host_count,
        min_operational_support: status.min_operational_support
      }
    end)
  end
end
