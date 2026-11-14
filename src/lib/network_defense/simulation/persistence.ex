defmodule NetworkDefense.Simulation.Persistence do
  @moduledoc false

  use Boundary,
    deps: [
      NetworkDefense,
      NetworkDefense.AttackerState,
      NetworkDefense.Graph,
      NetworkDefense.Repo
    ],
    exports: :all
end
