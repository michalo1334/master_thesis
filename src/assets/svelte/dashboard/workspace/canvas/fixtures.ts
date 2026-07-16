import { topologyEdges, topologyNodes } from "../../data";

export const NODE_WIDTH = 120;
export const NODE_HEIGHT = 72;

export type AssetKind = "Server" | "Workstation" | "Firewall" | "Database";

export interface CanvasNodeData {
  id: string;
  name: string;
  assetKind: AssetKind;
  address: string;
  status: string;
  risk: "Critical" | "High" | "Medium" | "Low" | "Untrusted";
  critical?: boolean;
  x: number;
  y: number;
}

export interface CanvasEdgeData {
  id: string;
  sourceId: string;
  targetId: string;
  relationshipLabel: string;
  visualStyle: CanvasEdgeVisualStyle;
}

export type CanvasEdgeVisualStyle = "standard" | "trust" | "warning";

export interface GraphPoint {
  x: number;
  y: number;
}

const fixtureAssetKinds: Record<string, AssetKind> = {
  internet: "Workstation",
  "edge-fw": "Firewall",
  vpn: "Firewall",
  web: "Server",
  api: "Server",
  worker: "Server",
  database: "Database",
  cache: "Database",
};

const assetDefaults: Record<
  AssetKind,
  Omit<CanvasNodeData, "id" | "name" | "x" | "y" | "assetKind">
> = {
  Server: { address: "10.0.20.0", status: "New asset", risk: "Medium" },
  Workstation: { address: "10.0.40.0", status: "New asset", risk: "Low" },
  Firewall: { address: "10.0.10.0", status: "Review rules", risk: "High" },
  Database: {
    address: "10.0.30.0",
    status: "New data store",
    risk: "Critical",
    critical: true,
  },
};

export function cloneFixtureGraph() {
  return {
    nodes: topologyNodes.map((node) => ({
      id: node.id,
      name: node.name,
      assetKind: fixtureAssetKinds[node.id],
      address: node.address,
      status: node.status,
      risk: node.risk,
      critical: node.critical,
      x: node.x,
      y: node.y,
    })),
    edges: topologyEdges.map(({ id, sourceId, targetId, label, warning }) => ({
      id,
      sourceId,
      targetId,
      relationshipLabel: label,
      visualStyle: warning ? "warning" : id === "fw-web" ? "trust" : "standard",
    })),
  } satisfies { nodes: CanvasNodeData[]; edges: CanvasEdgeData[] };
}

export function createFixtureNode(
  kind: AssetKind,
  position: GraphPoint,
  existingNodes: CanvasNodeData[],
) {
  const number =
    existingNodes.filter((node) => node.assetKind === kind).length + 1;
  const baseId = kind.toLowerCase();
  let candidate = `${baseId}-${number}`;
  let suffix = number;

  while (existingNodes.some((node) => node.id === candidate)) {
    suffix += 1;
    candidate = `${baseId}-${suffix}`;
  }

  return {
    id: candidate,
    name: `${kind} ${suffix}`,
    assetKind: kind,
    ...assetDefaults[kind],
    x: position.x - NODE_WIDTH / 2,
    y: position.y - NODE_HEIGHT / 2,
  } satisfies CanvasNodeData;
}

export function nodeCenter(node: CanvasNodeData): GraphPoint {
  return { x: node.x + NODE_WIDTH / 2, y: node.y + NODE_HEIGHT / 2 };
}

export function edgeEndpoints(source: CanvasNodeData, target: CanvasNodeData) {
  const sourceCenter = nodeCenter(source);
  const targetCenter = nodeCenter(target);
  const deltaX = targetCenter.x - sourceCenter.x;
  const deltaY = targetCenter.y - sourceCenter.y;
  const sourceScale = Math.min(
    NODE_WIDTH / 2 / Math.max(Math.abs(deltaX), Number.EPSILON),
    NODE_HEIGHT / 2 / Math.max(Math.abs(deltaY), Number.EPSILON),
  );
  const targetScale = Math.min(
    NODE_WIDTH / 2 / Math.max(Math.abs(deltaX), Number.EPSILON),
    NODE_HEIGHT / 2 / Math.max(Math.abs(deltaY), Number.EPSILON),
  );

  return {
    source: {
      x: sourceCenter.x + deltaX * sourceScale,
      y: sourceCenter.y + deltaY * sourceScale,
    },
    target: {
      x: targetCenter.x - deltaX * targetScale,
      y: targetCenter.y - deltaY * targetScale,
    },
  };
}
