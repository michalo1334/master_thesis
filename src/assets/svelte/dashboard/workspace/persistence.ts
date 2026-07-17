import {
  createTopologyEditor,
  type GraphEdge,
  type GraphNode,
  type TopologyDocument,
  type TopologyEditorState,
  type TopologyGraph,
  type WorkspaceSnapshot,
} from "./model";

const WORKSPACE_SCHEMA_VERSION = 3;
const topologyTools = new Set<TopologyEditorState["tool"]>([
  "select",
  "connect",
]);
const topologyLayouts = new Set<TopologyEditorState["layout"]>([
  "layered",
  "force-directed",
  "radial",
]);
const topologyPresentations = new Set<TopologyEditorState["presentation"]>([
  "graph",
  "list",
]);

interface PersistedTopologyEditor {
  tool: TopologyEditorState["tool"];
  selectedId?: string;
  connectionSourceId?: string;
  layout: TopologyEditorState["layout"];
  showZoneBoundaries: boolean;
  presentation: TopologyEditorState["presentation"];
}

interface PersistedTopologyDocument {
  id: string;
  title: string;
  type: "topology";
  graph: TopologyGraph;
  editor: PersistedTopologyEditor;
}

interface PersistedWorkspace {
  version: number;
  documents: PersistedTopologyDocument[];
  activeDocumentId?: string;
  nextDocumentId: number;
}

export function serializeWorkspace(snapshot: WorkspaceSnapshot): string {
  const documents = snapshot.documents.flatMap((document) => {
    if (document.type !== "topology") return [];

    return [
      {
        id: document.id,
        title: document.title,
        type: document.type,
        graph: document.graph,
        editor: {
          tool: document.editor.tool,
          selectedId: document.editor.selectedId,
          connectionSourceId: document.editor.connectionSourceId,
          layout: document.editor.layout,
          showZoneBoundaries: document.editor.showZoneBoundaries,
          presentation: document.editor.presentation,
        },
      },
    ];
  });
  const activeDocumentId = documents.some(
    (document) => document.id === snapshot.activeDocumentId,
  )
    ? snapshot.activeDocumentId
    : undefined;

  return JSON.stringify({
    version: WORKSPACE_SCHEMA_VERSION,
    documents,
    activeDocumentId,
    nextDocumentId: snapshot.nextDocumentId,
  } satisfies PersistedWorkspace);
}

export function parseWorkspace(
  serialized: string,
): WorkspaceSnapshot | undefined {
  let value: unknown;

  try {
    value = JSON.parse(serialized);
  } catch {
    return undefined;
  }

  if (!isPersistedWorkspace(value)) return undefined;

  const documents = value.documents.map(restoreTopologyDocument);
  const documentIds = new Set(documents.map((document) => document.id));

  if (documentIds.size !== documents.length) return undefined;
  if (value.activeDocumentId && !documentIds.has(value.activeDocumentId))
    return undefined;

  return {
    documents,
    activeDocumentId: value.activeDocumentId,
    nextDocumentId: value.nextDocumentId,
  };
}

function restoreTopologyDocument(
  document: PersistedTopologyDocument,
): TopologyDocument {
  return {
    id: document.id,
    title: document.title,
    type: "topology",
    graph: {
      id: document.graph.id,
      nodes: document.graph.nodes.map((node) => ({
        ...node,
        data: structuredClone(node.data),
      })),
      edges: document.graph.edges.map((edge) => ({
        ...edge,
        data: structuredClone(edge.data),
      })),
      positions: Object.fromEntries(
        Object.entries(document.graph.positions).map(([id, position]) => [
          id,
          { ...position },
        ]),
      ),
    },
    editor: {
      ...createTopologyEditor(),
      tool: document.editor.tool,
      selectedId: document.editor.selectedId,
      connectionSourceId: document.editor.connectionSourceId,
      layout: document.editor.layout,
      showZoneBoundaries: document.editor.showZoneBoundaries,
      presentation: document.editor.presentation,
    },
  };
}

function isPersistedWorkspace(value: unknown): value is PersistedWorkspace {
  if (!isRecord(value)) return false;

  return (
    value.version === WORKSPACE_SCHEMA_VERSION &&
    Array.isArray(value.documents) &&
    value.documents.every(isPersistedTopologyDocument) &&
    (value.activeDocumentId === undefined ||
      isNonEmptyString(value.activeDocumentId)) &&
    isAvailableNextDocumentId(value.nextDocumentId)
  );
}

function isPersistedTopologyDocument(
  value: unknown,
): value is PersistedTopologyDocument {
  if (!isRecord(value)) return false;

  return (
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.title) &&
    value.type === "topology" &&
    isTopologyGraph(value.graph) &&
    isPersistedTopologyEditor(value.editor)
  );
}

function isTopologyGraph(value: unknown): value is TopologyGraph {
  if (
    !isRecord(value) ||
    !isNonEmptyString(value.id) ||
    !Array.isArray(value.nodes) ||
    !value.nodes.every(isGraphNode) ||
    !Array.isArray(value.edges) ||
    !value.edges.every(isGraphEdge) ||
    !isPositionMap(value.positions)
  ) {
    return false;
  }

  const nodeIds = new Set(value.nodes.map((node) => node.id));
  const edgeIds = new Set(value.edges.map((edge) => edge.id));
  const positions = value.positions as TopologyGraph["positions"];

  return (
    nodeIds.size === value.nodes.length &&
    edgeIds.size === value.edges.length &&
    value.nodes.every((node) => node.graphId === value.id) &&
    value.edges.every(
      (edge) =>
        edge.graphId === value.id &&
        nodeIds.has(edge.fromId) &&
        nodeIds.has(edge.toId),
    ) &&
    Object.keys(positions).length === value.nodes.length &&
    value.nodes.every((node) => positions[node.id] !== undefined)
  );
}

function isGraphNode(value: unknown): value is GraphNode {
  return (
    isRecord(value) &&
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.graphId) &&
    isNonEmptyString(value.type) &&
    isJsonRecord(value.data)
  );
}

function isGraphEdge(value: unknown): value is GraphEdge {
  return (
    isRecord(value) &&
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.graphId) &&
    isNonEmptyString(value.fromId) &&
    isNonEmptyString(value.toId) &&
    isNonEmptyString(value.type) &&
    isJsonRecord(value.data)
  );
}

function isPositionMap(value: unknown): value is TopologyGraph["positions"] {
  return (
    isRecord(value) &&
    Object.values(value).every(
      (position) =>
        isRecord(position) &&
        isFiniteNumber(position.x) &&
        isFiniteNumber(position.y),
    )
  );
}

function isPersistedTopologyEditor(
  value: unknown,
): value is PersistedTopologyEditor {
  if (!isRecord(value)) return false;

  return (
    typeof value.tool === "string" &&
    topologyTools.has(value.tool as TopologyEditorState["tool"]) &&
    (value.selectedId === undefined || isNonEmptyString(value.selectedId)) &&
    (value.connectionSourceId === undefined ||
      isNonEmptyString(value.connectionSourceId)) &&
    typeof value.layout === "string" &&
    topologyLayouts.has(value.layout as TopologyEditorState["layout"]) &&
    typeof value.showZoneBoundaries === "boolean" &&
    typeof value.presentation === "string" &&
    topologyPresentations.has(
      value.presentation as TopologyEditorState["presentation"],
    )
  );
}

function isJsonRecord(value: unknown): value is Record<string, unknown> {
  return isRecord(value) && Object.values(value).every(isJsonValue);
}

function isJsonValue(value: unknown): boolean {
  return (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean" ||
    isFiniteNumber(value) ||
    (Array.isArray(value) && value.every(isJsonValue)) ||
    isJsonRecord(value)
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isAvailableNextDocumentId(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}
