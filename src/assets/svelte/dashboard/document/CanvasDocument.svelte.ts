import type { Graph } from "../contract";

export class CanvasDocument {
  private _graph: Graph;

  constructor(public graph: Graph) {
    this._graph = $state.snapshot(graph);
  }
}
