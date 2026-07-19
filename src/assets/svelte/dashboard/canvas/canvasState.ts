export interface Point {
  x: number;
  y: number;
}

export interface CanvasState {
  connectMode: boolean;
  connectionSourceId: string | undefined;
  zoom: number;
  pan: Point;
}

export type DragState =
  | {
      pointerId: number;
      start: Point;
      pan: Point;
    }
  | undefined;

export type NodeDragState =
  | {
      pointerId: number;
      nodeId: string;
      start: Point;
      nodePos: Point;
      moved: Boolean;
      element: SVGGElement;
    }
  | undefined;
