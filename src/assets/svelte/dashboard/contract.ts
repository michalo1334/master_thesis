export type Id = string;
export type Status = "ok" | "stale" | "not_found" | "unmapped_error";
export type RequestCorrelationId = number;

// contracts/open_graph.ex
export interface OpenGraphPayload {
  graph_id: Id;
}

export interface OpenGraphReply {
  status: Status;
  graph: LoadedGraph | null;
}

// contracts/save_graph.ex
export interface SaveGraphPayload {
  graph: LoadedGraph;
}

export interface SaveGraphReply {
  status: Status;
  graph: LoadedGraph | null;
}

// ---- Node data types ----
export interface HostData {
  name: string;
}

export interface ServiceData {
  name: string;
  protocol: "tcp" | "udp";
  port: number;
  version?: string;
}

export interface VulnerabilityData {
  identifier: string;
  cvss_score: number;
  exploit_probability: number;
}

// ---- Edge data types ----
export interface RunsData {}
export interface NetworkReachabilityData {}
export interface HasVulnerabilityData {}

// ---- Backend -> FE mapping tables ----
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

// contracts/graph.ex
export interface LoadedGraph {
  id: Id;
  title: string;
  lock_version: number;
  nodes: Node[];
  edges: Edge[];
}

export interface Node {
  id: Id;
  type: string;
  data: any;
  view_data: NodeViewData;
}

export interface NodeViewData {
  x_pos: number;
  y_pos: number;
}

export interface Edge {
  id: Id;
  from_id: Id;
  to_id: Id;
  type: string;
  data: any;
}

export type Selectable = Node | Edge;

// contracts/layout_graph.ex
export interface LayoutGraphParams {
  iterations: number;
  springLength: number;
  repulsion: number;
}

export interface LayoutGraphPayload {
  graph: LoadedGraph;
  params: LayoutGraphParams;
}

export interface LayoutGraphReply {
  status: Status;
  graph: LoadedGraph | null;
}

// Graph summary from the server (list_summaries)
export interface GraphSummary {
  id: Id;
  title: string;
  nodeCount: number;
  edgeCount: number;
}
