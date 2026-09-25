import type {
  Edge,
  GraphContract,
  Node,
} from "../../../contracts.generated/graph";
import type { ProjectTopologyDraftReply } from "../../../contracts.generated/dashboard/graph";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  TopologyProjectionModel,
  emptyTopologyProjection,
} from "../topology-projection-model.svelte";

const DOCUMENT_ID = "document-alpha";

function graph(overrides: Partial<GraphContract> = {}): GraphContract {
  return {
    id: "graph-1",
    title: "Graph",
    revision_id: "revision-1",
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    nodes: [],
    edges: [],
    ...overrides,
  };
}

function host(id: string, name = id): Node {
  return {
    id,
    type: "Host",
    data: { name },
    view_data: { x_pos: 0, y_pos: 0 },
  };
}

function runs(id: string, fromId: string, toId: string): Edge {
  return { id, type: "Runs", from_id: fromId, to_id: toId, data: {} };
}

function projection(marker = "projection") {
  return {
    ...emptyTopologyProjection(),
    segments: [
      {
        id: marker,
        host_ids: [],
        host_count: 0,
        service_count: 0,
        context_count: 0,
      },
    ],
  };
}

function okReply(
  documentId: string,
  semanticVersion: number,
  marker = "projection",
): ProjectTopologyDraftReply {
  return {
    status: "ok",
    document_id: documentId,
    semantic_version: semanticVersion,
    topology_projection: projection(marker),
    errors: [],
  };
}

async function echoReply(
  documentId: string,
  semanticVersion: number,
): Promise<ProjectTopologyDraftReply> {
  return okReply(documentId, semanticVersion, `projection-${semanticVersion}`);
}

function build(
  request?: (
    documentId: string,
    semanticVersion: number,
    graph: GraphContract,
  ) => Promise<ProjectTopologyDraftReply>,
  debounceMs = 300,
) {
  return new TopologyProjectionModel({
    documentId: DOCUMENT_ID,
    request,
    debounceMs,
  });
}

describe("TopologyProjectionModel", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  describe("initial state", () => {
    it("starts ready with an empty revision projection", () => {
      const model = build();

      expect(model.status).toBe("ready");
      expect(model.semanticVersion).toBe(0);
      expect(model.accepted.source).toBe("revision");
      expect(model.accepted.projection).toEqual(emptyTopologyProjection());
      expect(model.pendingEntityIds).toEqual([]);
    });
  });

  describe("semantic fingerprint", () => {
    it("increments the version when node type or data changes", async () => {
      const request = vi.fn(echoReply);
      const model = build(request);
      model.initializeFromRevision(graph(), projection());
      const base = model.semanticVersion;

      model.observeGraph(
        graph({ nodes: [host("host-1", "Gateway")] }),
        "immediate",
      );
      await vi.waitFor(() => expect(request).toHaveBeenCalledTimes(1));
      expect(model.semanticVersion).toBe(base + 1);

      model.observeGraph(
        graph({ nodes: [host("host-1", "Renamed gateway")] }),
        "immediate",
      );
      await vi.waitFor(() => expect(request).toHaveBeenCalledTimes(2));
      expect(model.semanticVersion).toBe(base + 2);
    });

    it("increments the version when edge endpoints or data change", async () => {
      const request = vi.fn(echoReply);
      const model = build(request);
      const nodes = [host("host-1"), host("host-2")];
      model.initializeFromRevision(graph({ nodes }), projection());
      const base = model.semanticVersion;

      const first = runs("edge-1", "host-1", "host-2");
      model.observeGraph(graph({ nodes, edges: [first] }), "immediate");
      await vi.waitFor(() => expect(request).toHaveBeenCalledTimes(1));

      model.observeGraph(
        graph({ nodes, edges: [{ ...first, to_id: "host-3" }] }),
        "immediate",
      );
      await vi.waitFor(() => expect(request).toHaveBeenCalledTimes(2));
      expect(model.semanticVersion).toBe(base + 2);
    });

    it("ignores title, revision metadata, and view_data changes", async () => {
      const request = vi.fn(echoReply);
      const model = build(request);
      const base = graph({ nodes: [host("host-1")] });
      model.initializeFromRevision(base, projection());
      const version = model.semanticVersion;

      model.observeGraph(
        {
          ...base,
          title: "Renamed graph",
          revision_id: "revision-2",
          revision_number: 9,
          nodes: [
            {
              ...(base.nodes[0] as Extract<Node, { type: "Host" }>),
              view_data: { x_pos: 480, y_pos: 260 },
            },
          ],
        },
        "immediate",
      );

      expect(request).not.toHaveBeenCalled();
      expect(model.semanticVersion).toBe(version);
      expect(model.status).toBe("ready");
    });
  });

  describe("request urgency", () => {
    it("sends a structural request immediately", async () => {
      const request = vi.fn(echoReply);
      const model = build(request);
      model.initializeFromRevision(graph(), projection());

      model.observeGraph(graph({ nodes: [host("host-1")] }), "immediate");

      expect(model.status).toBe("pending");
      await vi.waitFor(() => expect(request).toHaveBeenCalledTimes(1));
      expect(model.status).toBe("ready");
      expect(model.accepted.source).toBe("draft");
    });

    it("coalesces consecutive deferred edits into one request", async () => {
      vi.useFakeTimers();
      const request = vi.fn(echoReply);
      const model = build(request, 300);
      model.initializeFromRevision(graph(), projection());
      const base = model.semanticVersion;

      model.observeGraph(graph({ nodes: [host("host-1", "one")] }), "deferred");
      model.observeGraph(graph({ nodes: [host("host-1", "two")] }), "deferred");
      model.observeGraph(
        graph({ nodes: [host("host-1", "three")] }),
        "deferred",
      );

      expect(request).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(300);

      expect(request).toHaveBeenCalledTimes(1);
      expect(request.mock.calls[0][1]).toBe(model.semanticVersion);
      expect(model.semanticVersion).toBe(base + 3);
      expect(model.status).toBe("ready");
    });

    it("records the coalesced version as the requested version", async () => {
      vi.useFakeTimers();
      const sentVersions: number[] = [];
      const request = vi.fn(
        (_documentId: string, version: number) =>
          new Promise<ProjectTopologyDraftReply>(() => {
            sentVersions.push(version);
          }),
      );
      const model = build(request, 300);
      model.initializeFromRevision(graph(), projection());

      model.observeGraph(graph({ nodes: [host("host-1", "one")] }), "deferred");
      model.observeGraph(graph({ nodes: [host("host-1", "two")] }), "deferred");
      const latest = model.semanticVersion;

      await vi.advanceTimersByTimeAsync(300);

      expect(request).toHaveBeenCalledTimes(1);
      expect(sentVersions[0]).toBe(latest);
      expect(model.state).toMatchObject({
        status: "pending",
        requestedVersion: sentVersions[0],
      });
    });
  });

  describe("stale replies", () => {
    it("ignores a reply for an older semantic version", () => {
      const model = build();
      model.initializeFromRevision(graph(), projection("revision"));

      model.observeGraph(graph({ nodes: [host("host-1")] }), "immediate");
      const staleVersion = model.semanticVersion;
      model.observeGraph(
        graph({ nodes: [host("host-1")], edges: [runs("e", "a", "b")] }),
        "immediate",
      );

      model.acceptDraft(okReply(DOCUMENT_ID, staleVersion, "stale"));

      expect(model.accepted.projection.segments[0].id).toBe("revision");
    });

    it("fails the current request when the reply has no document id", () => {
      const model = build();
      model.initializeFromRevision(graph(), projection("revision"));
      model.observeGraph(graph({ nodes: [host("host-1")] }), "immediate");

      model.acceptDraft({
        status: "ok",
        document_id: null,
        semantic_version: model.semanticVersion,
        topology_projection: projection("foreign"),
        errors: [],
      });

      expect(model.status).toBe("error");
      expect(model.accepted.projection.segments[0].id).toBe("revision");
    });

    it("fails the current request when the reply document id mismatches", () => {
      const model = build();
      model.initializeFromRevision(graph(), projection("revision"));
      model.observeGraph(graph({ nodes: [host("host-1")] }), "immediate");

      model.acceptDraft(
        okReply("another-document", model.semanticVersion, "foreign"),
      );

      expect(model.status).toBe("error");
      expect(model.accepted.projection.segments[0].id).toBe("revision");
    });

    it("still ignores a stale reply with a foreign document id", () => {
      const model = build();
      model.initializeFromRevision(graph(), projection("revision"));
      model.observeGraph(graph({ nodes: [host("host-1")] }), "immediate");
      const staleVersion = model.semanticVersion;
      model.observeGraph(
        graph({ nodes: [host("host-1"), host("host-2")] }),
        "immediate",
      );

      model.acceptDraft(okReply("another-document", staleVersion, "foreign"));

      expect(model.status).toBe("pending");
      expect(model.accepted.projection.segments[0].id).toBe("revision");
    });

    it("ignores an in-flight reply that would collide with a later epoch", async () => {
      const pending: Array<{
        version: number;
        resolve: (reply: ProjectTopologyDraftReply) => void;
      }> = [];
      const request = vi.fn(
        (_documentId: string, version: number) =>
          new Promise<ProjectTopologyDraftReply>((resolve) => {
            pending.push({ version, resolve });
          }),
      );
      const model = build(request);

      model.initializeFromRevision(graph(), projection("revision-1"));
      model.observeGraph(graph({ nodes: [host("host-1")] }), "immediate");
      const staleVersion = model.semanticVersion;

      model.initializeFromRevision(
        graph({ nodes: [host("host-1")] }),
        projection("revision-2"),
      );
      model.observeGraph(
        graph({ nodes: [host("host-1"), host("host-2")] }),
        "immediate",
      );
      const currentVersion = model.semanticVersion;
      expect(currentVersion).toBeGreaterThan(staleVersion);

      pending[0].resolve(okReply(DOCUMENT_ID, pending[0].version, "collision"));
      await Promise.resolve();

      expect(model.accepted.projection.segments[0].id).toBe("revision-2");
      expect(model.status).toBe("pending");
    });

    it("applies the reply when document and version match", () => {
      const model = build();
      model.initializeFromRevision(graph(), projection("revision"));
      model.observeGraph(graph({ nodes: [host("host-1")] }), "immediate");

      model.acceptDraft(okReply(DOCUMENT_ID, model.semanticVersion, "fresh"));

      expect(model.status).toBe("ready");
      expect(model.accepted.source).toBe("draft");
      expect(model.accepted.projection.segments[0].id).toBe("fresh");
    });

    it("keeps the accepted projection after a failed request", () => {
      const model = build();
      model.initializeFromRevision(graph(), projection("revision"));
      model.observeGraph(graph({ nodes: [host("host-1")] }), "immediate");

      model.reject(model.semanticVersion);

      expect(model.status).toBe("error");
      expect(model.accepted.projection.segments[0].id).toBe("revision");
    });

    it("ignores a rejection for a superseded version", () => {
      const model = build();
      model.initializeFromRevision(graph(), projection("revision"));
      model.observeGraph(graph({ nodes: [host("host-1")] }), "immediate");
      const superseded = model.semanticVersion;
      model.observeGraph(
        graph({ nodes: [host("host-1"), host("host-2")] }),
        "immediate",
      );

      model.reject(superseded);

      expect(model.status).toBe("pending");
    });
  });

  describe("save conflicts", () => {
    it("accepts a saved projection captured at the same version", () => {
      const model = build();
      model.initializeFromRevision(graph(), projection("revision"));

      model.acceptSaved(projection("saved"), model.semanticVersion);

      expect(model.accepted.source).toBe("revision");
      expect(model.accepted.semanticVersion).toBe(model.semanticVersion);
      expect(model.accepted.projection.segments[0].id).toBe("saved");
    });

    it("ignores a saved projection when a newer edit exists", () => {
      const model = build();
      model.initializeFromRevision(graph(), projection("revision"));
      model.observeGraph(graph({ nodes: [host("host-1")] }), "immediate");

      model.acceptSaved(projection("stale-save"), 0);

      expect(model.accepted.projection.segments[0].id).toBe("revision");
      expect(model.status).toBe("pending");
    });
  });

  describe("deletion pruning", () => {
    it("drops pending entity state for deleted entities", () => {
      const model = build();
      model.initializeFromRevision(graph(), projection());

      model.observeGraph(
        graph({ nodes: [host("keep"), host("drop")] }),
        "deferred",
      );
      expect(model.pendingEntityIds).toEqual(["drop", "keep"]);

      model.pruneDeletedEntityState(graph({ nodes: [host("keep")] }));

      expect(model.pendingEntityIds).toEqual(["keep"]);
    });
  });
});
