defmodule NetworkDefense.AttackerState do
  @moduledoc false

  use Boundary,
    deps: [NetworkDefense],
    exports: [AttackerState, AttemptedAction, Graph]
end
