import type { Point } from "./canvasState";

/** Minimum screen-space movement that turns a press into a drag. */
export const DRAG_THRESHOLD = 4;

/** Screen-space difference between a gesture start and its current pointer. */
export function pointerDelta(start: Point, current: Point): Point {
  return { x: current.x - start.x, y: current.y - start.y };
}

/** True when a screen-space delta is large enough to count as a drag. */
export function exceedsDragThreshold(
  delta: Point,
  threshold = DRAG_THRESHOLD,
): boolean {
  return Math.hypot(delta.x, delta.y) >= threshold;
}

/** Converts a screen-space delta into world-space movement at the given zoom. */
export function screenDeltaToWorld(delta: Point, zoom: number): Point {
  const scale = zoom / 100;
  return { x: delta.x / scale, y: delta.y / scale };
}

/** Translates the positioned ids and skips ids without a recorded origin. */
export function translatePositionMap(
  ids: readonly string[],
  origins: ReadonlyMap<string, Point>,
  delta: Point,
): Map<string, Point> {
  const positions = new Map<string, Point>();
  for (const id of ids) {
    const origin = origins.get(id);
    if (origin)
      positions.set(id, { x: origin.x + delta.x, y: origin.y + delta.y });
  }
  return positions;
}
