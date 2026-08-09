export interface CanvasNodeAppearance {
  cardFill?: string;
  cardOpacity?: number;
  cardStroke?: string;
  cardStrokeWidth?: number;
}

export interface CanvasEdgeAppearance {
  opacity?: number;
  stroke?: string;
  strokeWidth?: number;
}

export interface CanvasStructuralFlow {
  id: string;
  sourceName: string;
  sourcePosition: { x: number; y: number };
  targetPosition: { x: number; y: number };
  serviceName: string;
}
