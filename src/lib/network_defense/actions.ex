defmodule NetworkDefense.Actions do
  @moduledoc false

  use Boundary,
    deps: [NetworkDefense, NetworkDefense.AttackerState],
    exports: [
      AcquireCredential,
      Action,
      AttemptedAction,
      ExploitVulnerability,
      Registry,
      ReuseCredential
    ]
end
