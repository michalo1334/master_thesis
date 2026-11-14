defmodule NetworkDefense.Graph do
  @moduledoc false

  use Boundary,
    deps: [
      NetworkDefense,
      NetworkDefense.Nodes,
      NetworkDefense.Relationships,
      NetworkDefense.Repo
    ],
    exports: :all
end
