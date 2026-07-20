defmodule NetworkDefenseWeb.Web.Contracts.ReportCharts do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          blast_radius_distribution: [NetworkDefenseWeb.Web.Contracts.ChartSpec.t()],
          convergence: [NetworkDefenseWeb.Web.Contracts.ChartSpec.t()],
          action_stats: [NetworkDefenseWeb.Web.Contracts.ChartSpec.t()]
        }
  defstruct [:blast_radius_distribution, :convergence, :action_stats]
end
