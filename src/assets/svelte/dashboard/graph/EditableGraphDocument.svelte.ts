import type { LoadedGraph } from "../contract";
import type { DashboardApi } from "../dashboard-api";
import type { ForceParams } from "./layout/ForceLayout.types";
import { applyForceLayout as runForceLayout } from "./layout/ForceLayout.svelte";

export type CanvasSelection =
  | { kind: "none" }
  | { kind: "node"; nodeId: string }
  | { kind: "edge"; edgeId: string };

function blankGraph(title: string): LoadedGraph {
  return {
    id: crypto.randomUUID(),
    title,
    lock_version: 0,
    nodes: [],
    edges: [],
  };
}

export class EditableGraphDocument {
  readonly kind = "graph" as const;
  readonly id: string;

  private _graph = $state<LoadedGraph>(blankGraph("Untitled"));
  private _selection = $state<CanvasSelection>({ kind: "none" });
  private _loaded = $state(false);
  private _loadedGraphId = $state<string | null>(null);
  private _lockVersion = $state(0);
  private _title = $state("Untitled");

  revision = $state(0);
  isSaving = $state(false);
  saveStatusMessage = $state("");

  constructor() {
    this.id = crypto.randomUUID();
  }

  get title(): string {
    return this._title;
  }

  get loaded(): boolean {
    return this._loaded;
  }

  get loadedGraphId(): string | null {
    return this._loadedGraphId;
  }

  get lockVersion(): number {
    return this._lockVersion;
  }

  get saveEligible(): boolean {
    return this._loaded;
  }

  get graph(): LoadedGraph {
    return this._graph;
  }

  set graph(value: LoadedGraph) {
    this._graph = value;
    this._preserveSelection(value);
  }

  get canvasSelection(): CanvasSelection {
    return this._selection;
  }

  get selection():
    LoadedGraph["nodes"][number] | LoadedGraph["edges"][number] | undefined {
    const sel = this._selection;
    if (sel.kind === "node")
      return this.graph.nodes.find((n) => n.id === sel.nodeId);
    if (sel.kind === "edge")
      return this.graph.edges.find((e) => e.id === sel.edgeId);
    return undefined;
  }

  selectNode(nodeId: string): void {
    this._selection = { kind: "node", nodeId };
  }

  selectEdge(edgeId: string): void {
    this._selection = { kind: "edge", edgeId };
  }

  clearSelection(): void {
    this._selection = { kind: "none" };
  }

  replaceFromLoadedGraph(graph: LoadedGraph): void {
    this._graph = graph;
    this._title = graph.title;
    this._loaded = true;
    this._loadedGraphId = graph.id;
    this._lockVersion = graph.lock_version;
    this._preserveSelection(graph);
  }

  replaceFromSaveReply(graph: LoadedGraph): void {
    this._graph = graph;
    this._title = graph.title;
    this._lockVersion = graph.lock_version;
    this._preserveSelection(graph);
  }

  async save(api: DashboardApi): Promise<void> {
    if (!this.saveEligible || this.isSaving) return;
    this.isSaving = true;
    try {
      const reply = await api.saveGraph(this._graph);
      if (reply.status === "ok" && reply.graph) {
        this.replaceFromSaveReply(reply.graph);
        this.saveStatusMessage = "Saved.";
      } else if (reply.status === "stale") {
        this.saveStatusMessage =
          "Save failed: graph was modified by another user.";
      } else if (reply.status === "not_found") {
        this.saveStatusMessage = "Save failed: graph no longer exists.";
      } else {
        this.saveStatusMessage = "Save failed.";
      }
    } finally {
      this.isSaving = false;
    }
  }

  async startSimulation(api: DashboardApi): Promise<{
    graphId: string;
    correlationId: string;
    graphTitle: string;
  } | null> {
    if (!this.loadedGraphId) return null;
    const correlationId = crypto.randomUUID();
    const reply = await api.runSimulation(this.loadedGraphId, correlationId);
    if (reply.status === "accepted") {
      return {
        graphId: reply.graph_id,
        correlationId: reply.correlation_id,
        graphTitle: this.title,
      };
    }
    return null;
  }

  applyForceLayout(params: ForceParams): void {
    runForceLayout(this._graph.nodes, this._graph.edges, params);
    this._graph = { ...this._graph };
    this.revision++;
  }

  private _preserveSelection(graph: LoadedGraph): void {
    const sel = this._selection;
    if (sel.kind === "node" && graph.nodes.some((n) => n.id === sel.nodeId))
      return;
    if (sel.kind === "edge" && graph.edges.some((e) => e.id === sel.edgeId))
      return;
    this._selection = { kind: "none" };
  }
}
