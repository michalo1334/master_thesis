import type {
  Edge,
  DashboardError,
  LoadedGraph,
  Node,
  OptimizationParams,
  RunOptimizationReply,
  SimulationParams,
} from "../contract";
import type { DashboardApi } from "../dashboard-api";
import type { IconName } from "../types";
import type { ForceParams } from "./layout/ForceLayout.types";
import { applyForceLayout as runForceLayout } from "./layout/ForceLayout.svelte";

export type CanvasSelection =
  | { kind: "none" }
  | { kind: "node"; nodeId: string }
  | { kind: "edge"; edgeId: string };

export interface ConnectionOption {
  relationshipType: Edge["type"];
  source: { id: string; type: Node["type"]; isFrom: boolean };
  target: { id?: string; type: Node["type"] };
}

export type StartSimulationResult =
  | {
      status: "accepted";
      graphId: string;
      graphRevisionId: string;
      correlationId: string;
      graphTitle: string;
    }
  | { status: "rejected"; error: DashboardError | null };

function blankGraph(title: string): LoadedGraph {
  return {
    id: crypto.randomUUID(),
    title,
    nodes: [],
    edges: [],
  };
}

export class EditableGraphDocument {
  readonly kind = "graph" as const;
  readonly icon = "graph" as const satisfies IconName;
  readonly id: string;

  private _graph = $state<LoadedGraph>(blankGraph("Untitled"));
  private _selection = $state<CanvasSelection>({ kind: "none" });
  private _loaded = $state(false);
  private _loadedRevisionId = $state<string | null>(null);
  private _title = $state("Untitled");
  private _changeVersion = $state(0);
  private _savedChangeVersion = $state(0);

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

  get loadedRevisionId(): string | null {
    return this._loadedRevisionId;
  }

  get saveEligible(): boolean {
    return this._loaded;
  }

  get isDirty(): boolean {
    return this._changeVersion !== this._savedChangeVersion;
  }

  get graph(): LoadedGraph {
    return this._graph;
  }

  set graph(value: LoadedGraph) {
    this._graph = value;
    this._changeVersion++;
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

  setTitle(title: string): void {
    const nextTitle = title.trim();
    if (!nextTitle || nextTitle === this._title) return;

    this._title = nextTitle;
    this.graph = { ...this._graph, title: nextTitle };
  }

  addNode(node: Node): void {
    this.graph = { ...this.graph, nodes: [...this.graph.nodes, node] };
    this.selectNode(node.id);
  }

  createConnection(edge: Edge, node?: Node): void {
    this.graph = {
      ...this.graph,
      nodes: node ? [...this.graph.nodes, node] : this.graph.nodes,
      edges: [...this.graph.edges, edge],
    };
    if (node) this.selectNode(node.id);
    else this.selectEdge(edge.id);
  }

  deleteSelection(): void {
    const selection = this._selection;
    if (selection.kind === "node") {
      this.graph = {
        ...this.graph,
        nodes: this.graph.nodes.filter((node) => node.id !== selection.nodeId),
        edges: this.graph.edges.filter(
          (edge) =>
            edge.from_id !== selection.nodeId &&
            edge.to_id !== selection.nodeId,
        ),
      };
    } else if (selection.kind === "edge") {
      this.graph = {
        ...this.graph,
        edges: this.graph.edges.filter((edge) => edge.id !== selection.edgeId),
      };
    }
  }

  updateSelection(selectable: Node | Edge): void {
    const selection = this._selection;
    if (
      selection.kind === "node" &&
      selectable.id === selection.nodeId &&
      "view_data" in selectable
    ) {
      this.graph = {
        ...this.graph,
        nodes: this.graph.nodes.map((node) =>
          node.id === selectable.id ? selectable : node,
        ),
      };
    } else if (
      selection.kind === "edge" &&
      selectable.id === selection.edgeId &&
      !("view_data" in selectable)
    ) {
      this.graph = {
        ...this.graph,
        edges: this.graph.edges.map((edge) =>
          edge.id === selectable.id ? selectable : edge,
        ),
      };
    }
  }

  replaceFromLoadedGraph(graph: LoadedGraph): void {
    this._graph = graph;
    this._title = graph.title;
    this._loaded = true;
    this._loadedRevisionId = graph.revision_id ?? null;
    this._savedChangeVersion = this._changeVersion;
    this._preserveSelection(graph);
  }

  replaceFromSaveReply(graph: LoadedGraph): void {
    this._graph = graph;
    this._title = graph.title;
    this._loadedRevisionId = graph.revision_id ?? null;
    this._savedChangeVersion = this._changeVersion;
    this._preserveSelection(graph);
  }

  async save(api: DashboardApi): Promise<boolean> {
    if (!this.saveEligible || this.isSaving) return false;
    this.isSaving = true;
    const savedChangeVersion = this._changeVersion;
    try {
      const reply = await api.saveGraph($state.snapshot(this._graph));
      if (reply.status === "ok" && reply.graph) {
        if (this._changeVersion === savedChangeVersion) {
          this.replaceFromSaveReply(reply.graph);
        } else {
          this._graph = { ...this._graph, ...revisionMetadata(reply.graph) };
          this._loadedRevisionId = reply.graph.revision_id ?? null;
          this._preserveSelection(this._graph);
        }
        this.saveStatusMessage = "Saved.";
        return true;
      } else if (reply.status === "not_found") {
        this.saveStatusMessage = "Save failed: graph no longer exists.";
      } else {
        this.saveStatusMessage = "Save failed.";
      }
      return false;
    } catch {
      this.saveStatusMessage = "Save failed.";
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  async saveIfDirty(api: DashboardApi): Promise<boolean> {
    if (!this.isDirty) return true;
    return (await this.save(api)) && !this.isDirty;
  }

  async startSimulation(
    api: DashboardApi,
    params: SimulationParams,
    correlationId: string = crypto.randomUUID(),
  ): Promise<StartSimulationResult | null> {
    if (!this.loadedRevisionId) return null;
    const reply = await api.runSimulation(
      this.loadedRevisionId,
      correlationId,
      params,
    );
    if (reply.status === "accepted") {
      return {
        status: "accepted",
        graphId: this.graph.id,
        graphRevisionId: reply.graph_revision_id,
        correlationId: reply.correlation_id,
        graphTitle: this.title,
      };
    }
    return { status: "rejected", error: reply.error ?? null };
  }

  async startOptimization(
    api: DashboardApi,
    params: OptimizationParams,
    correlationId: string = crypto.randomUUID(),
  ): Promise<RunOptimizationReply | null> {
    if (!this.loadedRevisionId) return null;
    return api.runOptimization(this.loadedRevisionId, correlationId, params);
  }

  applyForceLayout(params: ForceParams): void {
    runForceLayout(this._graph.nodes, this._graph.edges, params);
    this.graph = { ...this._graph };
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

function revisionMetadata(
  graph: LoadedGraph,
): Pick<
  LoadedGraph,
  | "id"
  | "revision_id"
  | "parent_revision_id"
  | "revision_kind"
  | "revision_number"
> {
  const {
    id,
    revision_id,
    parent_revision_id,
    revision_kind,
    revision_number,
  } = graph;
  return {
    id,
    revision_id,
    parent_revision_id,
    revision_kind,
    revision_number,
  };
}
