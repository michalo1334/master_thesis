defmodule NetworkDefense.Actions do
  @moduledoc false

  use Boundary,
    deps: [NetworkDefense],
    exports: [
      AcquireCredential,
      Action,
      AttemptedAction,
      ExploitVulnerability,
      Registry,
      ReuseCredential
    ]
end
