export type TopologyTool = "select" | "connect";
export type TopologyLayout = "layered" | "force-directed" | "radial";
export type TopologyPresentation = "graph" | "list";

export interface GraphPoint {
  x: number;
  y: number;
}

export interface GraphNode {
  id: string;
  graphId: string;
  type: string;
  data: Record<string, unknown>;
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
  nodes: GraphNode[];
  edges: GraphEdge[];
  positions: Record<string, GraphPoint>;
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
  nodes: readonly GraphNode[];
  edges: readonly GraphEdge[];
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
  activeDocumentId?: string;
  nextDocumentId: number;
}

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
    nodes: [...graph.nodes],
    edges: [...graph.edges],
    positions: createGridPositions(graph.nodes),
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

export function createGridPositions(
  nodes: readonly Pick<GraphNode, "id">[],
): Record<string, GraphPoint> {
  const columns = Math.max(1, Math.ceil(Math.sqrt(nodes.length)));

  return Object.fromEntries(
    [...nodes]
      .sort((left, right) => left.id.localeCompare(right.id))
      .map((node, index) => [
        node.id,
        {
          x: 80 + (index % columns) * 200,
          y: 80 + Math.floor(index / columns) * 120,
        },
      ]),
  );
}

export function cloneTopologyGraph(graph: TopologyGraph): TopologyGraph {
  return {
    id: graph.id,
    nodes: graph.nodes.map((node) => ({
      ...node,
      data: cloneGraphData(node.data),
    })),
    edges: graph.edges.map((edge) => ({
      ...edge,
      data: cloneGraphData(edge.data),
    })),
    positions: Object.fromEntries(
      Object.entries(graph.positions).map(([id, position]) => [
        id,
        { ...position },
      ]),
    ),
  };
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
    graph: cloneTopologyGraph(graph),
    editor: createTopologyEditor(),
  };
}

export function createSimulationDocument(
  id: string,
  title: string,
): SimulationDocument {
  return { id, title, type: "simulation" };
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
