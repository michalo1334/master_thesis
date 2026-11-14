defmodule NetworkDefense.Topology do
  @moduledoc false

  use Boundary,
    deps: [NetworkDefense],
    exports: [EnterpriseTopology, VulnerabilityCatalog]
end
