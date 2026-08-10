defmodule NetworkDefense.Simulation.SimulationReport.Charts do
  @moduledoc false

  @type t :: %__MODULE__{
          histogram: [map()],
          cdf: [map()],
          convergence: [map()],
          action_success: [map()],
          host_compromise: [map()],
          capability_impact: [map()],
          edge_traversal: [map()]
        }

  defstruct histogram: [],
            cdf: [],
            convergence: [],
            action_success: [],
            host_compromise: [],
            capability_impact: [],
            edge_traversal: []
end
