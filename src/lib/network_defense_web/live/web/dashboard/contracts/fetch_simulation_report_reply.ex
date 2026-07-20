defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationReportReply do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          multi_state_id: String.t(),
          graph_id: String.t(),
          graph_title: String.t(),
          graph_version_at_sim: integer(),
          simulation_count: integer(),
          iteration_count: integer(),
          total_runtime_ms: integer(),
          kpis: [NetworkDefenseWeb.Web.Contracts.KpiMetric.t()],
          charts: NetworkDefenseWeb.Web.Contracts.ReportCharts.t()
        }
  defstruct [
    :multi_state_id,
    :graph_id,
    :graph_title,
    :graph_version_at_sim,
    :simulation_count,
    :iteration_count,
    :total_runtime_ms,
    :kpis,
    :charts
  ]
end
