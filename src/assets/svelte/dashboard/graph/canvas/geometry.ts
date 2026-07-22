import type { NodeViewData } from "../../contract";
import type { Point } from "./canvasState";

export const NODE_WIDTH = 120;
export const NODE_HEIGHT = 72;

export function nodeCenter(position: Point): Point {
  return {
    x: position.x + NODE_WIDTH / 2,
    y: position.y + NODE_HEIGHT / 2,
  };
}

export function edgeEndpoints(sourcePosition: Point, targetPosition: Point) {
  const sourceCenter = nodeCenter(sourcePosition);
  const targetCenter = nodeCenter(targetPosition);
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
