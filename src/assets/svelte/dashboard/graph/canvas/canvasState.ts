export interface Point {
  x: number;
  y: number;
}

export interface ViewTransform {
  zoom: number;
  pan: Point;
}

export const MIN_ZOOM = 25;
export const MAX_ZOOM = 200;
export const ZOOM_STEP = 10;

export function clampZoom(value: number): number {
  return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, value));
}

export function formatWorldTransform({ pan, zoom }: ViewTransform): string {
  return `translate(${pan.x} ${pan.y}) scale(${zoom / 100})`;
}

export function screenToWorld(
  point: Point,
  { pan, zoom }: ViewTransform,
): Point {
  const scale = zoom / 100;
  return { x: (point.x - pan.x) / scale, y: (point.y - pan.y) / scale };
}

export function isActivationKey(key: string): boolean {
  return key === "Enter" || key === " ";
}

export interface CanvasState extends ViewTransform {
  connectMode: boolean;
  connectionSourceId: string | undefined;
}

export interface DragState {
  pointerId: number;
  start: Point;
  pan: Point;
}

export interface NodeDragState {
  pointerId: number;
  nodeId: string;
  start: Point;
  nodePos: Point;
  moved: boolean;
  element: SVGGElement;
}
