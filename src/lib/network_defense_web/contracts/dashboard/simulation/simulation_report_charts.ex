defmodule NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportCharts do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportActionSuccess
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportCapabilityImpact
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportCdfPoint
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportConvergencePoint
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportEdgeTraversal
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportHistogramBucket
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportHostCompromise

  embedded_schema do
    embeds_many :histogram,
                SimulationReportHistogramBucket,
                on_replace: :delete

    embeds_many :cdf, SimulationReportCdfPoint, on_replace: :delete

    embeds_many :convergence,
                SimulationReportConvergencePoint,
                on_replace: :delete

    embeds_many :action_success,
                SimulationReportActionSuccess,
                on_replace: :delete

    embeds_many :host_compromise,
                SimulationReportHostCompromise,
                on_replace: :delete

    embeds_many :capability_impact,
                SimulationReportCapabilityImpact,
                on_replace: :delete

    embeds_many :edge_traversal,
                SimulationReportEdgeTraversal,
                on_replace: :delete
  end

  @type t :: %__MODULE__{
          histogram: [
            SimulationReportHistogramBucket.t()
          ],
          cdf: [SimulationReportCdfPoint.t()],
          convergence: [
            SimulationReportConvergencePoint.t()
          ],
          action_success: [
            SimulationReportActionSuccess.t()
          ],
          host_compromise: [
            SimulationReportHostCompromise.t()
          ],
          capability_impact: [
            SimulationReportCapabilityImpact.t()
          ],
          edge_traversal: [
            SimulationReportEdgeTraversal.t()
          ]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:histogram)
    |> cast_embed(:cdf)
    |> cast_embed(:convergence)
    |> cast_embed(:action_success)
    |> cast_embed(:host_compromise)
    |> cast_embed(:capability_impact)
    |> cast_embed(:edge_traversal)
  end
end
