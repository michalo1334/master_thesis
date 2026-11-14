defmodule NetworkDefense.Relationships do
  @moduledoc false

  use Boundary,
    deps: [NetworkDefense],
    exports: [
      AuthenticatesTo,
      Contains,
      HasVulnerability,
      NetworkReachability,
      Registry,
      Runs,
      SegmentReachability,
      StoresCredential,
      Supports
    ]
end
