export type TopologyTool = "select" | "connect";
export type TopologyLayout = "layered" | "force-directed" | "radial";
export type TopologyPresentation = "graph" | "list";

export interface GraphPoint {
  x: number;
  y: number;
}

export type JsonPrimitive = null | boolean | number | string;
export type JsonValue = JsonPrimitive | JsonValue[] | JsonObject;

export interface JsonObject {
  [key: string]: JsonValue;
}

export interface GraphNodeViewData extends JsonObject {
  x_pos: number;
  y_pos: number;
}

export interface GraphNode {
  id: string;
  graphId: string;
  type: string;
  data: Record<string, unknown>;
  viewData: GraphNodeViewData;
}

export interface GraphEdge {
  id: string;
  graphId: string;
  fromId: string;
  toId: string;
  type: string;
  data: Record<string, unknown>;
}

export interface TopologyGraph {
  id: string;
  title: string;
  lockVersion: number;
  nodes: GraphNode[];
  edges: GraphEdge[];
}

export interface ServerGraphSummary {
  id: string;
  title: string;
  nodeCount: number;
  edgeCount: number;
}

export interface ServerTopologyGraph {
  id: string;
  title: string;
  lockVersion: number;
  nodes: readonly GraphNode[];
  edges: readonly GraphEdge[];
}

export interface TopologySavePayload {
  graph_id: string;
  lock_version: number;
  title: string;
  nodes: Array<{
    id: string;
    type: string;
    data: Record<string, unknown>;
    view_data: GraphNodeViewData;
  }>;
  edges: Array<{
    id: string;
    from_id: string;
    to_id: string;
    type: string;
    data: Record<string, unknown>;
  }>;
}

export interface TopologySaveReply {
  ok?: boolean;
  status?: string;
  stale?: boolean;
  error?: unknown;
  topology?: ServerTopologyGraph;
}

export interface TopologyEditorState {
  tool: TopologyTool;
  selectedId?: string;
  connectionSourceId?: string;
  zoom: number;
  pan: { x: number; y: number };
  layout: TopologyLayout;
  showZoneBoundaries: boolean;
  presentation: TopologyPresentation;
}

export interface TopologyDocument {
  id: string;
  title: string;
  type: "topology";
  graph: TopologyGraph;
  editor: TopologyEditorState;
}

export interface SimulationDocument {
  id: string;
  title: string;
  type: "simulation";
}

export type WorkspaceDocument = TopologyDocument | SimulationDocument;

export interface WorkspaceSnapshot {
  documents: WorkspaceDocument[];
  topologyBaselines: Record<string, string>;
  activeDocumentId?: string;
  nextDocumentId: number;
}

export interface SavedTopologyApplication {
  documents: WorkspaceDocument[];
  topologyBaselines: Record<string, string>;
}

export const NETWORK_REACHABILITY_TYPE =
  "Elixir.NetworkDefense.Relationships.NetworkReachability";

export function createTopologyEditor(): TopologyEditorState {
  return {
    tool: "select",
    selectedId: undefined,
    connectionSourceId: undefined,
    zoom: 100,
    pan: { x: 0, y: 0 },
    layout: "layered",
    showZoneBoundaries: true,
    presentation: "graph",
  };
}

export function topologyGraphFromServerGraph(
  graph: ServerTopologyGraph,
): TopologyGraph {
  return {
    id: graph.id,
    title: graph.title,
    lockVersion: graph.lockVersion,
    nodes: graph.nodes.map((node) => ({
      ...node,
      data: cloneGraphData(node.data),
      viewData: cloneJsonObject(node.viewData),
    })),
    edges: graph.edges.map((edge) => ({
      ...edge,
      data: cloneGraphData(edge.data),
    })),
  };
}

export function createTopologyDocumentFromServerGraph(
  documentId: string,
  graph: ServerTopologyGraph,
): TopologyDocument {
  return createTopologyDocument(
    documentId,
    graph.title,
    topologyGraphFromServerGraph(graph),
  );
}

export function cloneTopologyGraph(graph: TopologyGraph): TopologyGraph {
  return {
    id: graph.id,
    title: graph.title,
    lockVersion: graph.lockVersion,
    nodes: graph.nodes.map((node) => ({
      ...node,
      data: cloneGraphData(node.data),
      viewData: cloneJsonObject(node.viewData),
    })),
    edges: graph.edges.map((edge) => ({
      ...edge,
      data: cloneGraphData(edge.data),
    })),
  };
}

function cloneJsonObject<T extends JsonObject>(data: T): T {
  // LiveSvelte props can be reactive proxies, which structuredClone cannot copy.
  return JSON.parse(JSON.stringify(data)) as T;
}

function cloneGraphData(
  data: Record<string, unknown>,
): Record<string, unknown> {
  // LiveSvelte props can be reactive proxies, which structuredClone cannot copy.
  return JSON.parse(JSON.stringify(data)) as Record<string, unknown>;
}

export function createTopologyDocument(
  id: string,
  title: string,
  graph: TopologyGraph,
): TopologyDocument {
  return {
    id,
    title,
    type: "topology",
    graph: { ...cloneTopologyGraph(graph), title },
    editor: createTopologyEditor(),
  };
}

export function createSimulationDocument(
  id: string,
  title: string,
): SimulationDocument {
  return { id, title, type: "simulation" };
}

export function applySavedTopology(
  documents: readonly WorkspaceDocument[],
  topologyBaselines: Readonly<Record<string, string>>,
  documentId: string,
  topology: ServerTopologyGraph,
  submittedStateKey?: string,
): SavedTopologyApplication {
  const savedGraph = topologyGraphFromServerGraph(topology);
  const baseline = topologyEditableStateKey(savedGraph);
  const target = documents.find(
    (document) =>
      document.type === "topology" &&
      document.id === documentId &&
      document.graph.id === topology.id,
  );

  if (!target || target.type !== "topology") {
    return {
      documents: [...documents],
      topologyBaselines: { ...topologyBaselines },
    };
  }

  const hasNewerLocalEdits =
    submittedStateKey !== undefined &&
    topologyEditableStateKey(target.graph) !== submittedStateKey;

  return {
    documents: documents.map((document) =>
      document.type === "topology" && document.id === documentId
        ? hasNewerLocalEdits
          ? {
              ...document,
              title: document.graph.title,
              graph: { ...document.graph, lockVersion: topology.lockVersion },
            }
          : {
              ...document,
              title: topology.title,
              graph: cloneTopologyGraph(savedGraph),
            }
        : document,
    ),
    topologyBaselines: {
      ...topologyBaselines,
      [documentId]: baseline,
    },
  };
}

export function topologyEditableStateKey(graph: TopologyGraph): string {
  return JSON.stringify({
    title: graph.title,
    nodes: [...graph.nodes]
      .sort((left, right) => left.id.localeCompare(right.id))
      .map((node) => ({
        id: node.id,
        graphId: node.graphId,
        type: node.type,
        data: canonicalJsonValue(node.data),
        viewData: canonicalJsonValue(node.viewData),
      })),
    edges: [...graph.edges]
      .sort((left, right) => left.id.localeCompare(right.id))
      .map((edge) => ({
        id: edge.id,
        graphId: edge.graphId,
        fromId: edge.fromId,
        toId: edge.toId,
        type: edge.type,
        data: canonicalJsonValue(edge.data),
      })),
  });
}

export function topologySavePayload(graph: TopologyGraph): TopologySavePayload {
  return {
    graph_id: graph.id,
    lock_version: graph.lockVersion,
    title: graph.title,
    nodes: graph.nodes.map((node) => ({
      id: node.id,
      type: node.type,
      data: cloneGraphData(node.data),
      view_data: cloneJsonObject(node.viewData),
    })),
    edges: graph.edges.map((edge) => ({
      id: edge.id,
      from_id: edge.fromId,
      to_id: edge.toId,
      type: edge.type,
      data: cloneGraphData(edge.data),
    })),
  };
}

export function topologyFromSuccessfulSaveReply(
  reply: TopologySaveReply,
): ServerTopologyGraph | undefined {
  const statusIsFailure =
    reply.status !== undefined &&
    reply.status !== "ok" &&
    reply.status !== "success";

  if (
    reply.ok === false ||
    statusIsFailure ||
    reply.stale === true ||
    reply.error != null
  )
    return undefined;

  return reply.topology;
}

export function createNetworkReachabilityEdge(
  graphId: string,
  fromId: string,
  toId: string,
): GraphEdge {
  return {
    id: crypto.randomUUID(),
    graphId,
    fromId,
    toId,
    type: NETWORK_REACHABILITY_TYPE,
    data: {},
  };
}

export function canonicalJsonValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalJsonValue);
  if (typeof value !== "object" || value === null) return value;

  return Object.fromEntries(
    Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, entry]) => [key, canonicalJsonValue(entry)]),
  );
}

export function nextActiveDocumentId(
  documents: WorkspaceDocument[],
  activeDocumentId: string | undefined,
  closedDocumentId: string,
): string | undefined {
  if (activeDocumentId !== closedDocumentId) return activeDocumentId;

  const closedIndex = documents.findIndex(
    (document) => document.id === closedDocumentId,
  );
  const remainingDocuments = documents.filter(
    (document) => document.id !== closedDocumentId,
  );

  return (
    remainingDocuments[closedIndex]?.id ??
    remainingDocuments[closedIndex - 1]?.id
  );
}

export function graphTypeLabel(type: string): string {
  return type.split(".").at(-1) ?? type;
}

export function graphNodeLabel(node: GraphNode): string {
  return (
    stringMetadata(node.data, "name") ??
    stringMetadata(node.data, "identifier") ??
    graphTypeLabel(node.type)
  );
}

export function graphNodeMetadata(node: GraphNode): string {
  return Object.entries(node.data)
    .filter(
      ([, value]) => typeof value === "string" || typeof value === "number",
    )
    .map(([key, value]) => `${key}: ${value}`)
    .join(" | ");
}

function stringMetadata(data: Record<string, unknown>, key: string) {
  const value = data[key];
  return typeof value === "string" && value.trim() ? value : undefined;
}
