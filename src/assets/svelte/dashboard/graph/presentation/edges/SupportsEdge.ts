import CanvasEdgeInspector from "../../canvas/inspectors/CanvasEdgeInspector.svelte";

export const supportsEdge = {
  color: "var(--ui-color-node-mission-capability)",
  dashArray: "3 3" as string | null,
  inspector: CanvasEdgeInspector,
};
