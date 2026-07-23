import type { Edge } from "../../contract";

export interface EdgeStyle {
  color: string;
  dashArray: string | null;
}

const registry: Record<string, EdgeStyle> = {
  Runs: { color: "var(--ds-color-edge-runs)", dashArray: null },
  NetworkReachability: {
    color: "var(--ds-color-edge-reachability)",
    dashArray: "5 3",
  },
  HasVulnerability: {
    color: "var(--ds-color-edge-vulnerability)",
    dashArray: "2 3",
  },
};

export function edgeStyleFor(edge: Edge): EdgeStyle | null {
  return registry[edge.type] ?? null;
}
