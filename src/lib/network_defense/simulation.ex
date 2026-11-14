defmodule NetworkDefense.Simulation do
  @moduledoc false

  use Boundary,
    deps: [
      NetworkDefense,
      NetworkDefense.Actions,
      NetworkDefense.AttackerState,
      NetworkDefense.Compute,
      NetworkDefense.Graph,
      NetworkDefense.Nodes,
      NetworkDefense.Relationships,
      NetworkDefense.Repo,
      NetworkDefense.Rules
    ],
    exports: :all
end
