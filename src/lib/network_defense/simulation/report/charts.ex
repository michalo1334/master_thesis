defmodule NetworkDefense.Simulation.Report.Charts do
  @moduledoc false

  alias NetworkDefense.Simulation.Report.Chart

  @type t :: %__MODULE__{
          blast_radius_distribution: [Chart.t()],
          convergence: [Chart.t()],
          action_stats: [Chart.t()]
        }

  defstruct blast_radius_distribution: [], convergence: [], action_stats: []
end
