defmodule NetworkDefenseWeb.Web.Contracts.SimulationReportCharts do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    embeds_many :histogram, NetworkDefenseWeb.Web.Contracts.SimulationReportHistogramBucket,
      on_replace: :delete

    embeds_many :cdf, NetworkDefenseWeb.Web.Contracts.SimulationReportCdfPoint,
      on_replace: :delete

    embeds_many :convergence, NetworkDefenseWeb.Web.Contracts.SimulationReportConvergencePoint,
      on_replace: :delete

    embeds_many :action_success, NetworkDefenseWeb.Web.Contracts.SimulationReportActionSuccess,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          histogram: [NetworkDefenseWeb.Web.Contracts.SimulationReportHistogramBucket.t()],
          cdf: [NetworkDefenseWeb.Web.Contracts.SimulationReportCdfPoint.t()],
          convergence: [NetworkDefenseWeb.Web.Contracts.SimulationReportConvergencePoint.t()],
          action_success: [NetworkDefenseWeb.Web.Contracts.SimulationReportActionSuccess.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:histogram)
    |> cast_embed(:cdf)
    |> cast_embed(:convergence)
    |> cast_embed(:action_success)
  end
end
