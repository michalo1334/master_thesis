import type {
  Edge,
  GraphContract,
  Node,
} from "../../contracts.generated/graph";
import type {
  ProjectTopologyDraftReply,
  TopologyProjection,
} from "../../contracts.generated/dashboard/graph";

/** Debounce for consecutive inspector field edits. Structural edits flush at once. */
export const PROJECTION_DEBOUNCE_MS = 300;

export type ProjectionUrgency = "immediate" | "deferred";

export type ProjectionSource = "revision" | "draft";

export type AcceptedTopologyProjection = {
  source: ProjectionSource;
  semanticVersion: number;
  projection: TopologyProjection;
};

export type TopologyProjectionState =
  | { status: "ready"; accepted: AcceptedTopologyProjection }
  | {
      status: "pending";
      accepted: AcceptedTopologyProjection;
      requestedVersion: number;
    }
  | {
      status: "error";
      accepted: AcceptedTopologyProjection;
      failedVersion: number;
    };

export type ProjectionRequest = (
  documentId: string,
  semanticVersion: number,
  graph: GraphContract,
) => Promise<ProjectTopologyDraftReply>;

export interface TopologyProjectionModelOptions {
  documentId: string;
  request?: ProjectionRequest;
  debounceMs?: number;
}

export function emptyTopologyProjection(): TopologyProjection {
  return {
    segments: [],
    hosts: [],
    services: [],
    attachments: [],
    policy_groups: [],
    flow_groups: [],
    issues: [],
  };
}

/**
 * Owns semantic freshness for the editable document.
 *
 * The fingerprint covers node and edge identity, type, endpoints, and data.
 * It ignores the title, revision metadata, and every `view_data` field, so
 * geometry edits never request a new projection.
 */
export class TopologyProjectionModel {
  private readonly _documentId: string;
  private readonly _request?: ProjectionRequest;
  private readonly _debounceMs: number;

  private _semanticFingerprint = "";
  private _entitySignatures = new Map<string, string>();
  private _latestGraph?: GraphContract;
  private _timer?: ReturnType<typeof setTimeout>;
  private _disposed = false;

  private _semanticVersion = $state(0);
  private _state = $state.raw<TopologyProjectionState>({
    status: "ready",
    accepted: {
      source: "revision",
      semanticVersion: 0,
      projection: emptyTopologyProjection(),
    },
  });
  private _pendingEntityIds = $state.raw<string[]>([]);

  constructor(options: TopologyProjectionModelOptions) {
    this._documentId = options.documentId;
    this._request = options.request;
    this._debounceMs = options.debounceMs ?? PROJECTION_DEBOUNCE_MS;
  }

  get semanticFingerprint(): string {
    return this._semanticFingerprint;
  }

  get semanticVersion(): number {
    return this._semanticVersion;
  }

  get state(): TopologyProjectionState {
    return this._state;
  }

  get accepted(): AcceptedTopologyProjection {
    return this._state.accepted;
  }

  get acceptedProjection(): TopologyProjection {
    return this._state.accepted.projection;
  }

  get status(): TopologyProjectionState["status"] {
    return this._state.status;
  }

  /** Entities added or changed since the last accepted projection. */
  get pendingEntityIds(): readonly string[] {
    return this._pendingEntityIds;
  }

  /**
   * Compares the semantic fingerprint and requests a new projection when the
   * meaning changed. Structural edits request immediately. Inspector field
   * edits debounce. Geometry-only graphs do nothing.
   */
  observeGraph(graph: GraphContract, urgency: ProjectionUrgency): void {
    this._latestGraph = graph;
    const { fingerprint, signatures } = graphSemantics(graph);
    if (fingerprint === this._semanticFingerprint) {
      this.pruneDeletedEntityState(graph);
      return;
    }

    const changedIds: string[] = [];
    for (const [id, signature] of signatures) {
      if (this._entitySignatures.get(id) !== signature) changedIds.push(id);
    }
    const removedIds: string[] = [];
    for (const id of this._entitySignatures.keys()) {
      if (!signatures.has(id)) removedIds.push(id);
    }

    this._entitySignatures = signatures;
    this._semanticFingerprint = fingerprint;
    this._semanticVersion += 1;

    const pending = new Set(this._pendingEntityIds);
    for (const id of changedIds) pending.add(id);
    for (const id of removedIds) pending.delete(id);
    this._pendingEntityIds = [...pending].sort();

    this._state = {
      status: "pending",
      accepted: this._state.accepted,
      requestedVersion: this._semanticVersion,
    };

    if (urgency === "immediate") {
      this._cancelTimer();
      void this._flush(this._semanticVersion);
    } else {
      this._schedule();
    }
  }

  /**
   * Resets freshness against a revision projection from Open or Save.
   *
   * The semantic version never decreases. An in-flight request for an older
   * epoch therefore cannot collide with a version a later Open reuses.
   */
  initializeFromRevision(
    graph: GraphContract,
    projection: TopologyProjection,
  ): void {
    this._cancelTimer();
    this._latestGraph = graph;
    const { fingerprint, signatures } = graphSemantics(graph);
    this._semanticFingerprint = fingerprint;
    this._entitySignatures = signatures;
    this._semanticVersion += 1;
    this._pendingEntityIds = [];
    this._state = {
      status: "ready",
      accepted: {
        source: "revision",
        semanticVersion: this._semanticVersion,
        projection,
      },
    };
  }

  /**
   * Applies a draft reply only when the document and semantic version match.
   *
   * A reply for an older version is stale and changes nothing. A reply for the
   * current request that carries a missing or foreign document ID fails the
   * current request instead of leaving the projection pending forever.
   */
  acceptDraft(reply: ProjectTopologyDraftReply): void {
    const version =
      typeof reply.semantic_version === "number"
        ? reply.semantic_version
        : null;

    if (version !== null && version !== this._semanticVersion) return;

    if (reply.document_id !== this._documentId) {
      this.reject(this._semanticVersion);
      return;
    }

    if (version !== this._semanticVersion) {
      this.reject(this._semanticVersion);
      return;
    }

    if (reply.status === "ok" && reply.topology_projection) {
      this._state = {
        status: "ready",
        accepted: {
          source: "draft",
          semanticVersion: this._semanticVersion,
          projection: reply.topology_projection,
        },
      };
      this._pendingEntityIds = [];
      return;
    }

    this.reject(version);
  }

  /**
   * Accepts a saved projection only when no semantic edit happened since the
   * save started. A stale save reply cannot overwrite newer draft meaning.
   */
  acceptSaved(
    projection: TopologyProjection | null,
    savedSemanticVersion: number,
  ): void {
    if (!projection) return;
    if (savedSemanticVersion !== this._semanticVersion) return;
    this._state = {
      status: "ready",
      accepted: {
        source: "revision",
        semanticVersion: savedSemanticVersion,
        projection,
      },
    };
    this._pendingEntityIds = [];
  }

  /** Marks the current version as failed and keeps the last accepted projection. */
  reject(version: number): void {
    if (version !== this._semanticVersion) return;
    this._state = {
      status: "error",
      accepted: this._state.accepted,
      failedVersion: version,
    };
  }

  /** Drops per-entity state for entities that no longer exist in the graph. */
  pruneDeletedEntityState(graph: GraphContract): void {
    const existing = new Set<string>();
    for (const node of graph.nodes) existing.add(node.id);
    for (const edge of graph.edges) existing.add(edge.id);

    for (const id of [...this._entitySignatures.keys()]) {
      if (!existing.has(id)) this._entitySignatures.delete(id);
    }

    const next = this._pendingEntityIds.filter((id) => existing.has(id));
    if (next.length !== this._pendingEntityIds.length) {
      this._pendingEntityIds = next;
    }
  }

  /** Cancels a scheduled debounce and drops replies that arrive later. */
  dispose(): void {
    this._disposed = true;
    this._cancelTimer();
  }

  private _schedule(): void {
    this._cancelTimer();
    this._timer = setTimeout(() => {
      this._timer = undefined;
      void this._flush(this._semanticVersion);
    }, this._debounceMs);
  }

  private _cancelTimer(): void {
    if (this._timer === undefined) return;
    clearTimeout(this._timer);
    this._timer = undefined;
  }

  private async _flush(version: number): Promise<void> {
    const request = this._request;
    const graph = this._latestGraph;
    if (this._disposed || !request || !graph) return;

    this._state = {
      status: "pending",
      accepted: this._state.accepted,
      requestedVersion: version,
    };

    try {
      const reply = await request(this._documentId, version, graph);
      if (this._disposed) return;
      this.acceptDraft(reply);
    } catch {
      if (this._disposed) return;
      this.reject(version);
    }
  }
}

function nodeSignature(node: Node): string {
  return canonicalJson({ type: node.type, data: node.data });
}

function edgeSignature(edge: Edge): string {
  return canonicalJson({
    type: edge.type,
    from_id: edge.from_id,
    to_id: edge.to_id,
    data: edge.data,
  });
}

function graphSemantics(graph: GraphContract): {
  fingerprint: string;
  signatures: Map<string, string>;
} {
  const signatures = new Map<string, string>();
  for (const node of graph.nodes) signatures.set(node.id, nodeSignature(node));
  for (const edge of graph.edges) signatures.set(edge.id, edgeSignature(edge));

  const parts: string[] = [];
  for (const id of [...signatures.keys()].sort()) {
    parts.push(`${id}=${signatures.get(id)}`);
  }
  return { fingerprint: parts.join("|"), signatures };
}

function canonicalJson(value: unknown): string {
  if (value === undefined) return "undefined";
  if (value === null) return "null";
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  if (typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(record[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(String(value));
}
