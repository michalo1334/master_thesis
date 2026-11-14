defmodule NetworkDefense.Optimization do
  @moduledoc false

  use Boundary,
    deps: [
      NetworkDefense,
      NetworkDefense.AttackerState,
      NetworkDefense.DefenseActions,
      NetworkDefense.Graph,
      NetworkDefense.Relationships,
      NetworkDefense.Repo,
      NetworkDefense.Simulation
    ],
    exports: :all
end
