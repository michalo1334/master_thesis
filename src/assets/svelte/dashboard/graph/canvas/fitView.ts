import type { Node } from "../../contract";
import { clampZoom, type CanvasState } from "./canvasState";
import { NODE_HEIGHT, NODE_WIDTH } from "./geometry";

const PADDING = 60;

export interface FitViewInput {
  nodes: Node[];
  viewportWidth: number;
  viewportHeight: number;
}

/**
 * Computes the zoom and pan needed to fit all graph nodes within the viewport.
 * Returns `null` when there are no nodes (no-op).
 */
export function computeFitState(
  input: FitViewInput,
): Pick<CanvasState, "zoom" | "pan"> | null {
  if (input.nodes.length === 0) return null;

  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;

  for (const node of input.nodes) {
    const x = node.view_data.x_pos;
    const y = node.view_data.y_pos;
    minX = Math.min(minX, x);
    minY = Math.min(minY, y);
    maxX = Math.max(maxX, x + NODE_WIDTH);
    maxY = Math.max(maxY, y + NODE_HEIGHT);
  }

  const graphW = maxX - minX;
  const graphH = maxY - minY;
  const paddedW = graphW + 2 * PADDING;
  const paddedH = graphH + 2 * PADDING;

  const zoomX =
    input.viewportWidth > 0 ? (input.viewportWidth / paddedW) * 100 : Infinity;
  const zoomY =
    input.viewportHeight > 0
      ? (input.viewportHeight / paddedH) * 100
      : Infinity;
  const zoom = clampZoom(Math.min(zoomX, zoomY));

  const centerX = (minX + maxX) / 2;
  const centerY = (minY + maxY) / 2;
  const scale = zoom / 100;

  return {
    zoom,
    pan: {
      x: input.viewportWidth / 2 - centerX * scale,
      y: input.viewportHeight / 2 - centerY * scale,
    },
  };
}
