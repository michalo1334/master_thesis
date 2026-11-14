defmodule NetworkDefense.Optimization.Contracts do
  @moduledoc false

  use Boundary,
    deps: [NetworkDefense, NetworkDefense.DefenseActions],
    exports: [OptimizationParams, RunOptimizationRequest, SimulationSettings]
end
