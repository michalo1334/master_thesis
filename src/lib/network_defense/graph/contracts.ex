defmodule NetworkDefense.Graph.Contracts do
  @moduledoc false

  use Boundary,
    deps: [
      NetworkDefense,
      NetworkDefense.Nodes,
      NetworkDefense.Relationships
    ],
    exports: :all
end
