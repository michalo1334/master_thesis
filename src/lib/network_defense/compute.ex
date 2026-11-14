defmodule NetworkDefense.Compute do
  @moduledoc false

  use Boundary,
    deps: [NetworkDefense],
    exports: :all
end
