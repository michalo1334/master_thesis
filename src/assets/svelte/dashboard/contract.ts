import type {
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
  SimulationParams as GeneratedSimulationParams,
  FetchSimulationReportPayload,
  FetchSimulationReportReply,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  ExperimentSummary,
  FetchExperimentsPayload,
  FetchExperimentsReply,
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
  CredentialData,
  StoresCredentialData,
  AuthenticatesToData,
  CredentialNode,
  NetworkReachabilityEdge,
  HasVulnerabilityEdge,
  StoresCredentialEdge,
  AuthenticatesToEdge,
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
  FetchSimulationReportPayload,
  FetchSimulationReportReply,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  ExperimentSummary,
  FetchExperimentsPayload,
  FetchExperimentsReply,
  KpiMetric,
  ReportCharts,
  ChartSpec,
} from "../contracts.generated";

export type SimulationParams = GeneratedSimulationParams & {
  initial_foothold_node_id: string;
};

export type Id = string;
export type Status =
  "ok" | "stale" | "not_found" | "invalid_graph" | "unmapped_error";
export type RequestCorrelationId = number;

export type Selectable = Node | Edge;

export interface GraphSummary {
  id: Id;
  title: string;
  nodeCount: number;
  edgeCount: number;
}

export type SimulationReportData = FetchSimulationReportReply;
