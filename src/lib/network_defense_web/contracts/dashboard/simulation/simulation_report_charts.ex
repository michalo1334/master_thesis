defmodule NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportCharts do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    embeds_many :histogram,
                NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportHistogramBucket,
                on_replace: :delete

    embeds_many :cdf, NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportCdfPoint,
      on_replace: :delete

    embeds_many :convergence,
                NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportConvergencePoint,
                on_replace: :delete

    embeds_many :action_success,
                NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportActionSuccess,
                on_replace: :delete

    embeds_many :host_compromise,
                NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportHostCompromise,
                on_replace: :delete

    embeds_many :capability_impact,
                NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportCapabilityImpact,
                on_replace: :delete

    embeds_many :edge_traversal,
                NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportEdgeTraversal,
                on_replace: :delete
  end

  @type t :: %__MODULE__{
          histogram: [
            NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportHistogramBucket.t()
          ],
          cdf: [NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportCdfPoint.t()],
          convergence: [
            NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportConvergencePoint.t()
          ],
          action_success: [
            NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportActionSuccess.t()
          ],
          host_compromise: [
            NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportHostCompromise.t()
          ],
          capability_impact: [
            NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportCapabilityImpact.t()
          ],
          edge_traversal: [
            NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportEdgeTraversal.t()
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
