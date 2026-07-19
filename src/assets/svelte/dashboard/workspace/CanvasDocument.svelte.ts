import type { LoadedGraph, Selectable } from "../contract";
import type { DocumentBase } from "./WorkspaceDocument.svelte";

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

export class CanvasDocument implements DocumentBase {
  readonly kind = "canvas" as const;
  readonly id: string;

  private _graph = $state<LoadedGraph>(blankGraph("Untitled"));
  private _selection = $state<CanvasSelection>({ kind: "none" });
  private _loaded = $state(false);
  private _loadedGraphId = $state<string | null>(null);
  private _lockVersion = $state(0);
  private _title = $state("Untitled");

  constructor(title: string) {
    this.id = crypto.randomUUID();
    this._title = title;
    this._graph = blankGraph(title);
  }

  get title(): string {
    return this._title;
  }

  /** Whether this canvas was populated from a server-loaded graph. */
  get loaded(): boolean {
    return this._loaded;
  }

  /** The server-side graph id (null for blank canvases). */
  get loadedGraphId(): string | null {
    return this._loadedGraphId;
  }

  /** Optimistic-lock version from the last server reply. */
  get lockVersion(): number {
    return this._lockVersion;
  }

  /** True when the document is eligible for Save (loaded, not blank). */
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

  get selection(): Selectable | undefined {
    const selection = this._selection;

    if (selection.kind === "node")
      return this.graph.nodes.find((node) => node.id === selection.nodeId);
    if (selection.kind === "edge")
      return this.graph.edges.find((edge) => edge.id === selection.edgeId);

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

  /** Populate from a successful open_graph server reply. */
  replaceFromLoadedGraph(graph: LoadedGraph): void {
    this._graph = graph;
    this._title = graph.title;
    this._loaded = true;
    this._loadedGraphId = graph.id;
    this._lockVersion = graph.lock_version;
    this._preserveSelection(graph);
  }

  /** Update graph and lock version from a successful save_graph reply. */
  replaceFromSaveReply(graph: LoadedGraph): void {
    this._graph = graph;
    this._title = graph.title;
    this._lockVersion = graph.lock_version;
    this._preserveSelection(graph);
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
