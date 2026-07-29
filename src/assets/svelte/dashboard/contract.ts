import type {
  Node,
  Edge,
  GraphContract,
  OpenGraphPayload,
  OpenGraphReply,
  SaveGraphPayload,
  SaveGraphReply,
  RunSimulationRequest,
  RunSimulationPayload,
  RunSimulationReply,
  OptimizationParams,
  RunOptimizationReply,
  SimulationParams as GeneratedSimulationParams,
  FetchSimulationReportPayload,
  FetchSimulationReportReply,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  OptimizationCompletedEvent,
  OptimizationFailedEvent,
  ExperimentSummary,
  FetchExperimentsPayload,
  FetchExperimentsReply,
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
  OpenGraphPayload,
  OpenGraphReply,
  SaveGraphPayload,
  SaveGraphReply,
  RunSimulationRequest,
  RunSimulationPayload,
  RunSimulationReply,
  OptimizationParams,
  RunOptimizationReply,
  FetchSimulationReportPayload,
  FetchSimulationReportReply,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  OptimizationCompletedEvent,
  OptimizationFailedEvent,
  ExperimentSummary,
  FetchExperimentsPayload,
  FetchExperimentsReply,
} from "../contracts.generated";

export type LoadedGraph = GraphContract;

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
  parentId: string | null;
  tags: string[];
}

export type SimulationReportData = FetchSimulationReportReply;

export interface SimulationReportErrorEvent {
  experiment_id: string;
  graph_id: string;
  reason: string;
}
