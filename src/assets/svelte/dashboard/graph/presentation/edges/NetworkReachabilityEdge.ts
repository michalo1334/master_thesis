import CanvasEdgeInspector from "../../canvas/inspectors/CanvasEdgeInspector.svelte";

export const networkReachabilityEdge = {
  color: "var(--ds-color-edge-reachability)",
  dashArray: "5 3" as string | null,
  inspector: CanvasEdgeInspector,
};
