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

// Graph summary from the server (list_summaries)
export interface GraphSummary {
  id: Id;
  title: string;
  nodeCount: number;
  edgeCount: number;
}
