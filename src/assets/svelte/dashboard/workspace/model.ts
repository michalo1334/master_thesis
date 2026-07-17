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

export function cloneTopologyGraph(graph: TopologyGraph): TopologyGraph {
  return {
    id: graph.id,
    nodes: graph.nodes.map((node) => ({
      ...node,
      data: structuredClone(node.data),
    })),
    edges: graph.edges.map((edge) => ({
      ...edge,
      data: structuredClone(edge.data),
    })),
    positions: Object.fromEntries(
      Object.entries(graph.positions).map(([id, position]) => [
        id,
        { ...position },
      ]),
    ),
  };
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
