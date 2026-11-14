defmodule NetworkDefense.Simulation.Contracts do
  @moduledoc false

  use Boundary,
    deps: [NetworkDefense],
    exports: [RunSimulationRequest, SimulationParams]
end
