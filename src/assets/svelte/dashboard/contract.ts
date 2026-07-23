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
  RunSimulationReply,
  SimulationFailedEvent,
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
  RunSimulationReply,
  SimulationFailedEvent,
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

export type SimulationParams = {
  monte_carlo_trials: number;
  iterations_per_run: number;
};

export type RunSimulationRequest = {
  correlation_id: string;
  graph_id: string;
  simulation_params: SimulationParams;
};

export type RunSimulationPayload = {
  request: RunSimulationRequest;
};

export type FetchSimulationReportPayload = {
  graph_id: string;
  experiment_id: string;
};

export type FetchSimulationReportReply = {
  charts: ReportCharts;
  graph_id: string;
  graph_title: string;
  graph_version_at_sim: number;
  iteration_count: number;
  kpis: KpiMetric[];
  experiment_id: string;
  run_count: number;
  total_runtime_ms: number;
};

export type SimulationCompletedEvent = {
  correlation_id: string;
  graph_id: string;
  experiment_id: string;
};

export type ExperimentSummary = {
  id: string;
  graph_id: string;
  graph_title: string;
  seed: number;
  run_count: number;
  iteration_count: number;
  runtime_ms: number;
  started_at: string;
};

export type FetchExperimentsPayload = {
  graph_ids: string[];
};

export type FetchExperimentsReply = {
  experiments: ExperimentSummary[];
};
