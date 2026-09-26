import { clampZoom, type Point } from "../canvas/canvasState";

export interface Size {
  width: number;
  height: number;
}

export interface Rect extends Point, Size {}

/** Space kept around the content when the viewport fits the scene. */
export const FIT_PADDING = 60;

export function rectCenter(rect: Rect): Point {
  return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
}

export function offsetRect(rect: Rect, delta: Point): Rect {
  return { ...rect, x: rect.x + delta.x, y: rect.y + delta.y };
}

/**
 * Connects two rectangles with a straight line between their centers, clipped
 * at both borders. Segment frames and cards of different sizes stay accurate,
 * which is why the generic canvas edge primitive is not reused here.
 */
export function connectRects(
  source: Rect,
  target: Rect,
): { source: Point; target: Point } {
  const sourceCenter = rectCenter(source);
  const targetCenter = rectCenter(target);
  const length = Math.hypot(
    targetCenter.x - sourceCenter.x,
    targetCenter.y - sourceCenter.y,
  );
  if (length === 0) return { source: sourceCenter, target: targetCenter };

  const unit = {
    x: (targetCenter.x - sourceCenter.x) / length,
    y: (targetCenter.y - sourceCenter.y) / length,
  };

  return {
    source: {
      x: sourceCenter.x + unit.x * borderDistance(unit, source),
      y: sourceCenter.y + unit.y * borderDistance(unit, source),
    },
    target: {
      x:
        targetCenter.x -
        unit.x * borderDistance({ x: -unit.x, y: -unit.y }, target),
      y:
        targetCenter.y -
        unit.y * borderDistance({ x: -unit.x, y: -unit.y }, target),
    },
  };
}

/** Distance from the rectangle center to its border along a unit vector. */
function borderDistance(unit: Point, rect: Rect): number {
  const horizontal =
    unit.x === 0 ? Infinity : rect.width / 2 / Math.abs(unit.x);
  const vertical = unit.y === 0 ? Infinity : rect.height / 2 / Math.abs(unit.y);
  return Math.min(horizontal, vertical);
}

export function boundsOfRects(rects: readonly Rect[]): Rect | null {
  if (rects.length === 0) return null;

  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;

  for (const rect of rects) {
    minX = Math.min(minX, rect.x);
    minY = Math.min(minY, rect.y);
    maxX = Math.max(maxX, rect.x + rect.width);
    maxY = Math.max(maxY, rect.y + rect.height);
  }

  if (!Number.isFinite(minX) || !Number.isFinite(minY)) return null;
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

/**
 * Zoom and pan that fit every rectangle into the viewport.
 * Returns `null` when there is nothing to fit.
 */
export function fitRects(
  rects: readonly Rect[],
  viewport: { width: number; height: number },
  padding = FIT_PADDING,
): { zoom: number; pan: Point } | null {
  const bounds = boundsOfRects(rects);
  if (!bounds) return null;

  const paddedWidth = bounds.width + 2 * padding;
  const paddedHeight = bounds.height + 2 * padding;
  const zoom = clampZoom(
    Math.min(
      viewport.width > 0 ? (viewport.width / paddedWidth) * 100 : Infinity,
      viewport.height > 0 ? (viewport.height / paddedHeight) * 100 : Infinity,
    ),
  );

  const center = rectCenter(bounds);
  const scale = zoom / 100;
  return {
    zoom,
    pan: {
      x: viewport.width / 2 - center.x * scale,
      y: viewport.height / 2 - center.y * scale,
    },
  };
}

export function rectAt(position: Point, size: Size): Rect {
  return { x: position.x, y: position.y, ...size };
}

/** Node card placed by the projection scene and measured by the layout. */
export function nodeRect(position: Point, size: Size): Rect {
  return rectAt(position, size);
}

/** Inclusive pointer hit-testing for canvas elements. */
export function pointInRect(point: Point, rect: Rect): boolean {
  return (
    point.x >= rect.x &&
    point.x <= rect.x + rect.width &&
    point.y >= rect.y &&
    point.y <= rect.y + rect.height
  );
}

/** Strict interior containment for layout decisions. */
export function pointInRectInterior(point: Point, rect: Rect): boolean {
  return (
    point.x > rect.x &&
    point.x < rect.x + rect.width &&
    point.y > rect.y &&
    point.y < rect.y + rect.height
  );
}

export function inflateRect(rect: Rect, gap: number): Rect {
  return {
    x: rect.x - gap,
    y: rect.y - gap,
    width: rect.width + 2 * gap,
    height: rect.height + 2 * gap,
  };
}

export function rectanglesOverlap(a: Rect, b: Rect, gap = 0): boolean {
  return (
    a.x < b.x + b.width + gap &&
    b.x < a.x + a.width + gap &&
    a.y < b.y + b.height + gap &&
    b.y < a.y + a.height + gap
  );
}

export function frameRect(frame: { position: Point; size: Size }): Rect {
  return rectAt(frame.position, frame.size);
}
