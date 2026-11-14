defmodule NetworkDefense.Evaluation2 do
  @moduledoc false

  use Boundary,
    deps: [
      NetworkDefense,
      NetworkDefense.AttackerState,
      NetworkDefense.DefenseActions,
      NetworkDefense.Graph,
      NetworkDefense.Nodes,
      NetworkDefense.Optimization,
      NetworkDefense.Optimizations,
      NetworkDefense.Repo,
      NetworkDefense.Rules,
      NetworkDefense.Simulation,
      NetworkDefense.Simulations
    ],
    exports: :all
end
