defmodule NetworkDefense.Rules do
  @moduledoc false

  use Boundary,
    deps: [
      NetworkDefense,
      NetworkDefense.Actions,
      NetworkDefense.AttackerState,
      NetworkDefense.Graph,
      NetworkDefense.Nodes,
      NetworkDefense.Relationships
    ],
    exports: :all
end
