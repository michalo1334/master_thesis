import type {
  HostData,
  ServiceData,
  VulnerabilityData,
  RunsData,
  NetworkReachabilityData,
  HasVulnerabilityData,
  NodeViewData,
  Node,
  Edge,
  GraphContract as LoadedGraph,
  OpenGraphPayload,
  OpenGraphReply,
  SaveGraphPayload,
  SaveGraphReply,
  RunSimulationRequest,
  RunSimulationPayload,
  RunSimulationReply,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  SimulationRunSummary,
  FetchSimulationReportPayload,
  FetchSimulationReportReply,
  FetchSimulationRunsPayload,
  FetchSimulationRunsReply,
  KpiMetric,
  ReportCharts,
  ChartSpec,
} from "../contracts.generated";

export type {
  HostData,
  ServiceData,
  VulnerabilityData,
  RunsData,
  NetworkReachabilityData,
  HasVulnerabilityData,
  NodeViewData,
  Node,
  Edge,
  GraphContract as LoadedGraph,
  OpenGraphPayload,
  OpenGraphReply,
  SaveGraphPayload,
  SaveGraphReply,
  RunSimulationRequest,
  RunSimulationPayload,
  RunSimulationReply,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  SimulationRunSummary,
  FetchSimulationReportPayload,
  FetchSimulationReportReply,
  FetchSimulationRunsPayload,
  FetchSimulationRunsReply,
  KpiMetric,
  ReportCharts,
  ChartSpec,
} from "../contracts.generated";

export type Id = string;
export type Status =
  "ok" | "stale" | "not_found" | "invalid_graph" | "unmapped_error";
export type RequestCorrelationId = number;

export type NodeDataByType = {
  Host: HostData;
  Service: ServiceData;
  Vulnerability: VulnerabilityData;
};

export type EdgeDataByType = {
  Runs: RunsData;
  NetworkReachability: NetworkReachabilityData;
  HasVulnerability: HasVulnerabilityData;
};

export type Selectable = Node | Edge;

export interface GraphSummary {
  id: Id;
  title: string;
  nodeCount: number;
  edgeCount: number;
}

export type SimulationReportData = FetchSimulationReportReply;
