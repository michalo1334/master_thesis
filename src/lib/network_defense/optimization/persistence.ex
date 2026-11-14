defmodule NetworkDefense.Optimization.Persistence do
  @moduledoc false

  use Boundary,
    deps: [
      NetworkDefense,
      NetworkDefense.DefenseActions,
      NetworkDefense.Graph,
      NetworkDefense.Optimization.Contracts,
      NetworkDefense.Repo
    ],
    exports: :all
end
