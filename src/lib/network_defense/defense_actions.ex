defmodule NetworkDefense.DefenseActions do
  @moduledoc false

  use Boundary,
    deps: [NetworkDefense],
    exports: [
      BlockSegmentReachability,
      DefenseAction,
      PatchVulnerability,
      Registry,
      RevokeCredential
    ]
end
