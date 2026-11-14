defmodule NetworkDefense.Tooling do
  @moduledoc false

  use Boundary,
    top_level?: true,
    deps: [NetworkDefense, NetworkDefenseWeb]
end
