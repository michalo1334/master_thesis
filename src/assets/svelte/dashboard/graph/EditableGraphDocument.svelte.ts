import type {
  Edge,
  GraphContract,
  Node,
} from "../../contracts.generated/graph";
import type { DashboardError } from "../../contracts.generated/dashboard";
import type {
  GraphValidationError,
  TopologyProjection,
} from "../../contracts.generated/dashboard/graph";
import type { OptimizationParams } from "../../contracts.generated/optimization";
import type { RunOptimizationReply } from "../../contracts.generated/dashboard/optimization";
import type { SimulationParams } from "../../contracts.generated/simulation";
import type { DashboardApi } from "../dashboard-api";
import { WorkspaceDocumentBase } from "../workspace/WorkspaceDocument.svelte";
import {
  TopologyProjectionModel,
  type AcceptedTopologyProjection,
  type ProjectionUrgency,
  type TopologyProjectionState,
} from "./topology-projection-model.svelte";
import type { DashboardRecoveryContext } from "../workspace/recovery-context";
import {
  isPersistedDocumentOfKind,
  type PersistedWorkspaceDocument,
} from "../../ui-kit/workspace/workspace-persistence";

export type CanvasSelection =
  | { kind: "none" }
  | { kind: "node"; nodeId: string }
  | { kind: "edge"; edgeId: string };

export interface ConnectionOption {
  relationshipType: Edge["type"];
  source: {
    id: string;
    type: Node["type"];
    isFrom: boolean;
  };
  target: { id?: string; type: Node["type"] };
}

export type StartSimulationResult =
  | {
      status: "accepted";
      graphId: string;
      graphRevisionId: string;
      correlationId: string;
      runId: string;
      graphTitle: string;
    }
  | {
      status: "rejected";
      error: DashboardError | null;
    };

function blankGraph(title: string): GraphContract {
  return {
    id: crypto.randomUUID(),
    title,
    nodes: [],
    edges: [],
  };
}

export class EditableGraphDocument extends WorkspaceDocumentBase {
  readonly kind = "graph" as const;
  readonly documentLabel = "Graph";
  readonly icon = "graph" as const satisfies string;
  static readonly createOption = {
    id: "graph",
    label: "Graph",
    icon: "graph" as const,
  };
  readonly id: string;

  private _graph = $state<GraphContract>(blankGraph("Untitled"));
  private _selection = $state<CanvasSelection>({ kind: "none" });
  private _pinnedEntityIds = $state<string[]>([]);
  private _loaded = $state(false);
  private _loadedRevisionId = $state<string | null>(null);
  private _title = $state("Untitled");
  private _changeVersion = $state(0);
  private _savedChangeVersion = $state(0);
  private _saveErrors = $state<GraphValidationError[]>([]);
  private _api?: DashboardApi;
  private readonly _projection: TopologyProjectionModel;

  isSaving = $state(false);
  saveStatusMessage = $state("");

  constructor(title = "Untitled") {
    super();
    this._graph = blankGraph(title);
    this._title = title;
    this.id = crypto.randomUUID();
    this._projection = new TopologyProjectionModel({
      documentId: this.id,
      request: (documentId, semanticVersion, graph) => {
        const api = this._api;
        if (!api) {
          return Promise.resolve({
            status: "unmapped_error" as const,
            document_id: documentId,
            semantic_version: semanticVersion,
            topology_projection: null,
            errors: [],
          });
        }
        return api.projectTopologyDraft(documentId, semanticVersion, graph);
      },
    });
  }

  static fromPersisted(
    data: unknown,
    _context: DashboardRecoveryContext,
  ): EditableGraphDocument | undefined {
    if (!isGraphPersisted(data)) return undefined;
    const document = new EditableGraphDocument(data.title);
    document.setPersisted(data);
    return document;
  }

  toPersisted(): PersistedWorkspaceDocument | undefined {
    if (!this.loaded || !this.loadedRevisionId || this.isDirty)
      return undefined;
    return {
      kind: "graph",
      ids: { revisionId: this.loadedRevisionId },
      title: this.title,
    };
  }

  needsRecovery(): boolean {
    return !this.loaded && this.persistedData !== undefined;
  }

  recover(context: DashboardRecoveryContext): void {
    const persisted = this.persistedData as PersistedGraph | undefined;
    if (!persisted) return;
    this.attachApi(context.api);
    void (async () => {
      try {
        const reply = await context.api.openGraph(persisted.ids.revisionId);
        if (
          reply.status !== "ok" ||
          !reply.graph ||
          !reply.topology_projection
        ) {
          context.workspace.statusMessage = "Failed to open graph.";
          return;
        }
        this.replaceFromLoadedGraph(reply.graph, reply.topology_projection);
        context.workspace.upsertGraphSummary(reply.graph);
        context.workspace.ensureInitialFoothold(this);
      } catch {
        context.workspace.statusMessage = "Failed to open graph.";
      }
    })();
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

  get graph(): GraphContract {
    return this._graph;
  }

  set graph(value: GraphContract) {
    this._applyGraph(value, "immediate");
  }

  get topologyProjection(): TopologyProjection {
    return this._projection.acceptedProjection;
  }

  get topologyProjectionState(): TopologyProjectionState {
    return this._projection.state;
  }

  get acceptedProjection(): AcceptedTopologyProjection {
    return this._projection.accepted;
  }

  get projectionStatus(): TopologyProjectionState["status"] {
    return this._projection.status;
  }

  get pendingProjectionEntityIds(): readonly string[] {
    return this._projection.pendingEntityIds;
  }

  /** Composes the API used for draft projection requests. */
  attachApi(api: DashboardApi): void {
    this._api = api;
  }

  dispose(): void {
    this._projection.dispose();
  }

  get canvasSelection(): CanvasSelection {
    return this._selection;
  }

  /**
   * Entities whose adjacency lens stays visible after selection moves.
   *
   * Pins are view state. They never enter the graph, the projection request,
   * or the dirty comparison.
   */
  get pinnedEntityIds(): readonly string[] {
    return this._pinnedEntityIds;
  }

  isPinned(entityId: string): boolean {
    return this._pinnedEntityIds.includes(entityId);
  }

  togglePin(entityId: string): void {
    if (!this._graph.nodes.some((node) => node.id === entityId)) return;
    this._pinnedEntityIds = this._pinnedEntityIds.includes(entityId)
      ? this._pinnedEntityIds.filter((id) => id !== entityId)
      : [...this._pinnedEntityIds, entityId].sort();
  }

  clearPins(): void {
    this._pinnedEntityIds = [];
  }

  get selectedValidationErrors(): readonly GraphValidationError[] {
    const selection = this._selection;
    if (selection.kind === "node") {
      return this._saveErrors.filter(
        (error) =>
          error.entity_kind === "node" && error.entity_id === selection.nodeId,
      );
    }
    if (selection.kind === "edge") {
      return this._saveErrors.filter(
        (error) =>
          error.entity_kind === "edge" && error.entity_id === selection.edgeId,
      );
    }
    return [];
  }

  get graphValidationErrors(): readonly GraphValidationError[] {
    return this._saveErrors.filter((error) => error.entity_kind === "graph");
  }

  get selection():
    | GraphContract["nodes"][number]
    | GraphContract["edges"][number]
    | undefined {
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
    this._saveErrors = this._saveErrors.filter(
      (error) => error.entity_kind !== "graph",
    );
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

  /**
   * Geometry-only update for drag frames.
   *
   * Positions never change projection semantics, so this path skips the
   * semantic fingerprint entirely: a pointer move must not walk the whole
   * graph. It still marks the document dirty because positions persist with
   * the graph.
   */
  setNodePositions(
    positions: ReadonlyMap<string, { x: number; y: number }>,
  ): void {
    if (positions.size === 0) return;

    let changed = false;
    const nodes = this._graph.nodes.map((node): Node => {
      const next = positions.get(node.id);
      if (
        !next ||
        (next.x === node.view_data.x_pos && next.y === node.view_data.y_pos)
      ) {
        return node;
      }
      changed = true;
      return {
        ...node,
        view_data: { ...node.view_data, x_pos: next.x, y_pos: next.y },
      };
    });
    if (!changed) return;

    this._graph = { ...this._graph, nodes };
    this._changeVersion++;
  }

  updateSelection(selectable: Node | Edge): void {
    const selection = this._selection;
    if (
      selection.kind === "node" &&
      selectable.id === selection.nodeId &&
      "view_data" in selectable
    ) {
      this._applyGraph(
        {
          ...this.graph,
          nodes: this.graph.nodes.map((node) =>
            node.id === selectable.id ? selectable : node,
          ),
        },
        "deferred",
      );
      this._clearValidationErrors("node", selectable.id);
    } else if (
      selection.kind === "edge" &&
      selectable.id === selection.edgeId &&
      !("view_data" in selectable)
    ) {
      this._applyGraph(
        {
          ...this.graph,
          edges: this.graph.edges.map((edge) =>
            edge.id === selectable.id ? selectable : edge,
          ),
        },
        "deferred",
      );
      this._clearValidationErrors("edge", selectable.id);
    }
  }

  replaceFromLoadedGraph(
    graph: GraphContract,
    projection: TopologyProjection,
  ): void {
    this._graph = graph;
    this._title = graph.title;
    this._loaded = true;
    this._loadedRevisionId = graph.revision_id ?? null;
    this._savedChangeVersion = this._changeVersion;
    this._saveErrors = [];
    this._preserveSelection(graph);
    this._projection.initializeFromRevision(graph, projection);
  }

  replaceFromSaveReply(
    graph: GraphContract,
    projection: TopologyProjection | null,
    savedSemanticVersion: number,
  ): void {
    const projectionIsCurrent =
      projection != null &&
      savedSemanticVersion === this._projection.semanticVersion;
    this._graph = graph;
    this._title = graph.title;
    this._loadedRevisionId = graph.revision_id ?? null;
    this._savedChangeVersion = this._changeVersion;
    this._saveErrors = [];
    this._preserveSelection(graph);
    if (projectionIsCurrent && projection) {
      this._projection.initializeFromRevision(graph, projection);
    }
  }

  async save(api: DashboardApi): Promise<boolean> {
    if (!this.saveEligible || this.isSaving) return false;
    this.attachApi(api);
    this.isSaving = true;
    const savedChangeVersion = this._changeVersion;
    const savedSemanticVersion = this._projection.semanticVersion;
    try {
      const reply = await api.saveGraph($state.snapshot(this._graph));
      if (reply.status === "ok" && reply.graph) {
        if (this._changeVersion === savedChangeVersion) {
          this.replaceFromSaveReply(
            reply.graph,
            reply.topology_projection ?? null,
            savedSemanticVersion,
          );
        } else {
          this._graph = { ...this._graph, ...revisionMetadata(reply.graph) };
          this._loadedRevisionId = reply.graph.revision_id ?? null;
          this._preserveSelection(this._graph);
          if (savedSemanticVersion === this._projection.semanticVersion) {
            this._projection.acceptSaved(
              reply.topology_projection ?? null,
              savedSemanticVersion,
            );
          }
        }
        this._saveErrors = [];
        this.saveStatusMessage = "Saved.";
        return true;
      } else if (reply.status === "not_found") {
        this.saveStatusMessage = "Save failed: graph no longer exists.";
      } else {
        this._saveErrors =
          this._changeVersion === savedChangeVersion
            ? (reply.errors ?? [])
            : [];
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
        runId: reply.run_id ?? "",
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

  private _applyGraph(value: GraphContract, urgency: ProjectionUrgency): void {
    this._graph = value;
    this._changeVersion++;
    this._preserveSelection(value);
    const snapshot = $state.snapshot(value) as GraphContract;
    this._projection.observeGraph(snapshot, urgency);
    this._projection.pruneDeletedEntityState(snapshot);
  }

  private _preserveSelection(graph: GraphContract): void {
    const pinned = this._pinnedEntityIds.filter((id) =>
      graph.nodes.some((node) => node.id === id),
    );
    if (pinned.length !== this._pinnedEntityIds.length)
      this._pinnedEntityIds = pinned;
    this._saveErrors = this._saveErrors.filter(
      (error) =>
        error.entity_kind === "graph" ||
        (error.entity_kind === "node" &&
          graph.nodes.some((node) => node.id === error.entity_id)) ||
        (error.entity_kind === "edge" &&
          graph.edges.some((edge) => edge.id === error.entity_id)),
    );
    const sel = this._selection;
    if (sel.kind === "node" && graph.nodes.some((n) => n.id === sel.nodeId))
      return;
    if (sel.kind === "edge" && graph.edges.some((e) => e.id === sel.edgeId))
      return;
    this._selection = { kind: "none" };
  }

  private _clearValidationErrors(
    entityKind: "node" | "edge",
    entityId: string,
  ): void {
    this._saveErrors = this._saveErrors.filter(
      (error) =>
        error.entity_kind !== entityKind || error.entity_id !== entityId,
    );
  }
}

type PersistedGraph = PersistedWorkspaceDocument & {
  ids: { revisionId: string };
};

function isGraphPersisted(value: unknown): value is PersistedGraph {
  return isPersistedDocumentOfKind<PersistedGraph["ids"]>(value, "graph", [
    "revisionId",
  ]);
}

function revisionMetadata(
  graph: GraphContract,
): Pick<
  GraphContract,
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
