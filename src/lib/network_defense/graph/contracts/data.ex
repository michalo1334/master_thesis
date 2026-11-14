defmodule NetworkDefense.Graph.Contracts.Data do
  @moduledoc false

  use Boundary,
    deps: [NetworkDefense, NetworkDefense.Nodes],
    exports: [
      AuthenticatesToData,
      ContainsData,
      CredentialData,
      CvssData,
      HasVulnerabilityData,
      HostData,
      MissionCapabilityData,
      NetworkSegmentData,
      RequiredServiceFlowData,
      RunsData,
      SegmentReachabilityData,
      ServiceData,
      StoresCredentialData,
      SupportsData,
      VulnerabilityData
    ]
end
