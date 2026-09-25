import type { GraphContract } from "../../../contracts.generated/graph";
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { EditableGraphDocument } from "../EditableGraphDocument.svelte";
import type { DashboardApi } from "../../dashboard-api";

function makeGraph(overrides: Partial<GraphContract> = {}): GraphContract {
  return {
    id: "g1",
    title: "Graph",
    revision_id: "r1",
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    nodes: [],
    edges: [],
    ...overrides,
  };
}

function hostNode(id: string, xPos = 0, yPos = 0) {
  return {
    id,
    type: "Host" as const,
    data: { name: id },
    view_data: { x_pos: xPos, y_pos: yPos },
  };
}

function runsEdge(id: string) {
  return { id, from_id: "a", to_id: "b", type: "Runs" as const, data: {} };
}

function serviceNode(id: string) {
  return {
    id,
    type: "Service" as const,
    data: { name: id, protocol: "tcp" as const, port: 443, version: null },
    view_data: { x_pos: 0, y_pos: 0 },
  };
}

describe("EditableGraphDocument", () => {
  let doc: EditableGraphDocument;

  beforeEach(() => {
    doc = new EditableGraphDocument();
  });

  describe("initial state", () => {
    it("has kind graph", () => {
      expect(doc.kind).toBe("graph");
    });

    it("has no title", () => {
      expect(doc.title).toBe("Untitled");
    });

    it("has a non-empty id", () => {
      expect(doc.id).toBeTruthy();
      expect(typeof doc.id).toBe("string");
    });

    it("has no selection initially", () => {
      expect(doc.canvasSelection.kind).toBe("none");
    });

    it("has a blank graph initially", () => {
      expect(doc.graph.nodes).toEqual([]);
      expect(doc.graph.edges).toEqual([]);
    });

    it("is not loaded initially", () => {
      expect(doc.loaded).toBe(false);
    });

    it("has null loadedRevisionId initially", () => {
      expect(doc.loadedRevisionId).toBeNull();
    });

    it("is not save eligible initially", () => {
      expect(doc.saveEligible).toBe(false);
    });

    it("starts not saving", () => {
      expect(doc.isSaving).toBe(false);
    });
  });

  describe("selection", () => {
    it("selectNode sets selection to node kind", () => {
      doc.selectNode("node-1");
      expect(doc.canvasSelection).toEqual({ kind: "node", nodeId: "node-1" });
    });

    it("resolves a selected node", () => {
      const node = hostNode("node-1");
      doc.graph = makeGraph({ nodes: [node] });
      doc.selectNode(node.id);
      expect(doc.selection).toStrictEqual(node);
    });

    it("selectEdge sets selection to edge kind", () => {
      doc.selectEdge("edge-1");
      expect(doc.canvasSelection).toEqual({ kind: "edge", edgeId: "edge-1" });
    });

    it("clearSelection resets to none", () => {
      doc.selectNode("node-1");
      doc.clearSelection();
      expect(doc.canvasSelection).toEqual({ kind: "none" });
    });
  });

  describe("graph setter preserves valid selection", () => {
    it("retains node selection when node still exists", () => {
      const existingGraph = makeGraph({ nodes: [hostNode("node-1")] });
      doc.graph = existingGraph;
      doc.selectNode("node-1");
      doc.graph = { ...existingGraph, id: "g2" };
      expect(doc.canvasSelection).toEqual({ kind: "node", nodeId: "node-1" });
    });

    it("clears node selection when node removed", () => {
      const existingGraph = makeGraph({ nodes: [hostNode("node-1")] });
      doc.graph = existingGraph;
      doc.selectNode("node-1");
      doc.graph = makeGraph();
      expect(doc.canvasSelection.kind).toBe("none");
    });
  });

  describe("loaded graph behavior", () => {
    it("replaceFromLoadedGraph marks document as loaded", () => {
      const graph = makeGraph({
        id: "server-g",
        title: "Server Topology",
        revision_id: "r3",
        nodes: [hostNode("n1", 10, 20)],
      });
      doc.replaceFromLoadedGraph(graph, emptyProjection());
      expect(doc.loaded).toBe(true);
      expect(doc.loadedRevisionId).toBe("r3");
      expect(doc.title).toBe("Server Topology");
      expect(doc.saveEligible).toBe(true);
    });

    it("updates the title and marks the graph dirty", () => {
      doc.replaceFromLoadedGraph(
        makeGraph({ title: "Original" }),
        emptyProjection(),
      );

      doc.setTitle("  Renamed graph  ");

      expect(doc.title).toBe("Renamed graph");
      expect(doc.graph.title).toBe("Renamed graph");
      expect(doc.isDirty).toBe(true);
    });

    it("replaceFromSaveReply updates graph and revision", () => {
      doc.replaceFromLoadedGraph(
        makeGraph({ id: "sg", revision_id: "r1", title: "V1" }),
        emptyProjection(),
      );
      const updated = makeGraph({ id: "sg", title: "V2", revision_id: "r2" });
      doc.replaceFromSaveReply(
        updated,
        emptyProjection(),
        doc.acceptedProjection.semanticVersion,
      );
      expect(doc.loadedRevisionId).toBe("r2");
      expect(doc.title).toBe("V2");
    });
  });

  describe("geometry-only updates", () => {
    it("moves a node without requesting a projection", () => {
      const projectTopologyDraft = vi.fn();
      doc.attachApi({ projectTopologyDraft } as unknown as DashboardApi);
      doc.replaceFromLoadedGraph(
        makeGraph({ nodes: [hostNode("n1", 10, 20)] }),
        emptyProjection(),
      );

      doc.setNodePositions(new Map([["n1", { x: 400, y: 250 }]]));

      expect(doc.graph.nodes[0]!.view_data).toEqual({ x_pos: 400, y_pos: 250 });
      expect(projectTopologyDraft).not.toHaveBeenCalled();
      expect(doc.projectionStatus).toBe("ready");
      expect(doc.isDirty).toBe(true);
    });

    it("ignores unknown entities and unchanged positions", () => {
      doc.replaceFromLoadedGraph(
        makeGraph({ nodes: [hostNode("n1", 10, 20)] }),
        emptyProjection(),
      );

      doc.setNodePositions(
        new Map([
          ["missing", { x: 1, y: 2 }],
          ["n1", { x: 10, y: 20 }],
        ]),
      );

      expect(doc.graph.nodes[0]!.view_data).toEqual({ x_pos: 10, y_pos: 20 });
      expect(doc.isDirty).toBe(false);
    });
  });

  describe("saving", () => {
    it("skips clean graphs when saving if dirty", async () => {
      doc.replaceFromLoadedGraph(makeGraph(), emptyProjection());
      const api = { saveGraph: vi.fn() } as unknown as DashboardApi;

      await expect(doc.saveIfDirty(api)).resolves.toBe(true);
      expect(api.saveGraph).not.toHaveBeenCalled();
    });

    it("reports manual save success and failure", async () => {
      doc.replaceFromLoadedGraph(makeGraph(), emptyProjection());
      doc.addNode(hostNode("first"));
      const api = {
        saveGraph: vi
          .fn()
          .mockResolvedValueOnce(
            makeSaveReply(makeGraph({ revision_id: "r2" })),
          )
          .mockResolvedValueOnce({ status: "invalid_graph" }),
      } as unknown as DashboardApi;

      await expect(doc.save(api)).resolves.toBe(true);
      expect(doc.saveStatusMessage).toBe("Saved.");
      expect(doc.isDirty).toBe(false);

      doc.addNode(hostNode("second"));
      await expect(doc.save(api)).resolves.toBe(false);
      expect(doc.saveStatusMessage).toBe("Save failed.");
      expect(doc.isDirty).toBe(true);
    });

    it("keeps validation errors on the selected entity until it changes", async () => {
      const node = hostNode("host-1");
      doc.replaceFromLoadedGraph(
        makeGraph({ nodes: [node] }),
        emptyProjection(),
      );
      doc.selectNode(node.id);
      doc.updateSelection({ ...node, data: { name: "" } });
      const api = {
        saveGraph: vi.fn().mockResolvedValue({
          status: "invalid_graph",
          errors: [
            {
              entity_kind: "node",
              entity_id: node.id,
              field_path: ["name"],
              message: "can't be blank",
            },
          ],
        }),
      } as unknown as DashboardApi;

      await expect(doc.save(api)).resolves.toBe(false);
      expect(doc.selectedValidationErrors).toHaveLength(1);

      doc.updateSelection({ ...node, data: { name: "Updated" } });
      expect(doc.selectedValidationErrors).toEqual([]);
    });

    it("clears validation errors when replacing or removing their entities", async () => {
      const node = hostNode("host-1");
      doc.replaceFromLoadedGraph(
        makeGraph({ nodes: [node] }),
        emptyProjection(),
      );
      doc.selectNode(node.id);
      const api = {
        saveGraph: vi.fn().mockResolvedValue({
          status: "invalid_graph",
          errors: [
            {
              entity_kind: "node",
              entity_id: node.id,
              field_path: ["name"],
              message: "can't be blank",
            },
            {
              entity_kind: "graph",
              entity_id: null,
              field_path: [],
              message: "Graph is invalid",
            },
          ],
        }),
      } as unknown as DashboardApi;

      await doc.save(api);
      expect(doc.selectedValidationErrors).toHaveLength(1);
      expect(doc.graphValidationErrors).toHaveLength(1);

      doc.deleteSelection();
      expect(doc.selectedValidationErrors).toEqual([]);

      doc.replaceFromLoadedGraph(makeGraph(), emptyProjection());
      expect(doc.graphValidationErrors).toEqual([]);
    });

    it("clears graph validation errors when the title changes", async () => {
      doc.replaceFromLoadedGraph(makeGraph(), emptyProjection());
      const api = {
        saveGraph: vi.fn().mockResolvedValue({
          status: "unmapped_error",
          errors: [
            {
              entity_kind: "graph",
              entity_id: null,
              field_path: [],
              message: "invalid_edge",
            },
          ],
        }),
      } as unknown as DashboardApi;

      await doc.save(api);
      expect(doc.graphValidationErrors).toHaveLength(1);

      doc.setTitle("Renamed");
      expect(doc.graphValidationErrors).toEqual([]);
    });

    it("saves a changed title in the graph payload", async () => {
      doc.replaceFromLoadedGraph(
        makeGraph({ title: "Original" }),
        emptyProjection(),
      );
      doc.setTitle("Renamed");
      const api = {
        saveGraph: vi
          .fn()
          .mockResolvedValue(
            makeSaveReply(makeGraph({ title: "Renamed", revision_id: "r2" })),
          ),
      } as unknown as DashboardApi;

      await expect(doc.save(api)).resolves.toBe(true);

      expect(api.saveGraph).toHaveBeenCalledWith(
        expect.objectContaining({ title: "Renamed" }),
      );
    });

    it("keeps edits made while saving dirty", async () => {
      doc.replaceFromLoadedGraph(makeGraph(), emptyProjection());
      doc.addNode(hostNode("first"));
      let resolveSave!: (
        value: Awaited<ReturnType<DashboardApi["saveGraph"]>>,
      ) => void;
      const api = {
        saveGraph: vi.fn(
          () =>
            new Promise<Awaited<ReturnType<DashboardApi["saveGraph"]>>>(
              (resolve) => {
                resolveSave = resolve;
              },
            ),
        ),
      } as unknown as DashboardApi;

      const saving = doc.save(api);
      doc.addNode(hostNode("second"));
      resolveSave(makeSaveReply(makeGraph({ revision_id: "r2" })));

      await expect(saving).resolves.toBe(true);
      expect(doc.graph.nodes.map((node) => node.id)).toEqual([
        "first",
        "second",
      ]);
      expect(doc.loadedRevisionId).toBe("r2");
      expect(doc.isDirty).toBe(true);
    });
  });

  describe("canvas editing", () => {
    it("appends and selects a node draft", () => {
      const node = serviceNode("service");
      doc.addNode(node);

      expect(doc.graph.nodes).toEqual([node]);
      expect(doc.canvasSelection).toEqual({ kind: "node", nodeId: node.id });
    });

    it("appends and selects an edge draft", () => {
      const host = hostNode("host");
      const service = serviceNode("service");
      doc.graph = makeGraph({ nodes: [host, service] });
      const edge = {
        id: "runs",
        type: "Runs" as const,
        from_id: host.id,
        to_id: service.id,
        data: {},
      };

      doc.createConnection(edge);

      expect(doc.graph.edges).toEqual([edge]);
      expect(doc.canvasSelection).toEqual({ kind: "edge", edgeId: edge.id });
    });

    it("appends a node and edge draft, selecting the node", () => {
      const service = serviceNode("service");
      doc.graph = makeGraph({ nodes: [service] });
      const host = hostNode("host", 30, 40);
      const edge = {
        id: "runs",
        type: "Runs" as const,
        from_id: host.id,
        to_id: service.id,
        data: {},
      };

      doc.createConnection(edge, host);

      expect(doc.graph.nodes).toEqual([service, host]);
      expect(doc.graph.edges).toEqual([edge]);
      expect(doc.canvasSelection).toEqual({ kind: "node", nodeId: host.id });
    });

    it("deletes a node and its incident edges", () => {
      const host = hostNode("host");
      const service = serviceNode("service");
      const edge = {
        id: "edge",
        type: "Runs" as const,
        from_id: host.id,
        to_id: service.id,
        data: {},
      };
      doc.graph = makeGraph({ nodes: [host, service], edges: [edge] });
      doc.selectNode(host.id);

      doc.deleteSelection();

      expect(doc.graph.nodes).toEqual([service]);
      expect(doc.graph.edges).toEqual([]);
      expect(doc.canvasSelection).toEqual({ kind: "none" });
    });

    it("updates the selected item in memory", () => {
      const host = hostNode("host");
      doc.graph = makeGraph({ nodes: [host] });
      doc.selectNode(host.id);

      doc.updateSelection({ ...host, data: { name: "Renamed host" } });

      expect(doc.selection).toMatchObject({ data: { name: "Renamed host" } });
    });
  });

  describe("pins", () => {
    it("toggles a node pin without marking the graph dirty", () => {
      doc.replaceFromLoadedGraph(
        makeGraph({ nodes: [hostNode("host-1"), hostNode("host-2")] }),
        emptyProjection(),
      );

      doc.togglePin("host-2");
      doc.togglePin("host-1");

      expect(doc.pinnedEntityIds).toEqual(["host-1", "host-2"]);
      expect(doc.isPinned("host-1")).toBe(true);
      expect(doc.isDirty).toBe(false);
    });

    it("unpins a pinned entity and clears every pin", () => {
      doc.graph = makeGraph({
        nodes: [hostNode("host-1"), hostNode("host-2")],
      });
      doc.togglePin("host-1");
      doc.togglePin("host-2");

      doc.togglePin("host-1");
      expect(doc.pinnedEntityIds).toEqual(["host-2"]);

      doc.clearPins();
      expect(doc.pinnedEntityIds).toEqual([]);
      expect(doc.isPinned("host-2")).toBe(false);
    });

    it("ignores a pin for an entity the graph does not contain", () => {
      doc.graph = makeGraph({ nodes: [hostNode("host-1")] });

      doc.togglePin("missing-host");

      expect(doc.pinnedEntityIds).toEqual([]);
    });

    it("drops a stale pin when its entity is deleted", () => {
      doc.graph = makeGraph({
        nodes: [hostNode("host-1"), hostNode("host-2")],
      });
      doc.togglePin("host-1");
      doc.togglePin("host-2");
      doc.selectNode("host-1");

      doc.deleteSelection();

      expect(doc.pinnedEntityIds).toEqual(["host-2"]);
      expect(doc.canvasSelection).toEqual({ kind: "none" });
    });

    it("drops a pin that the reloaded graph no longer contains", () => {
      doc.graph = makeGraph({
        nodes: [hostNode("host-1"), hostNode("host-2")],
      });
      doc.togglePin("host-1");

      doc.replaceFromLoadedGraph(
        makeGraph({ revision_id: "r2", nodes: [hostNode("host-2")] }),
        emptyProjection(),
      );

      expect(doc.pinnedEntityIds).toEqual([]);
    });
  });

  describe("projection lifecycle", () => {
    afterEach(() => {
      vi.useRealTimers();
    });

    function projection(marker: string) {
      return {
        ...emptyProjection(),
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

    function markerOf(): string | undefined {
      return doc.topologyProjection.segments[0]?.id;
    }

    function draftApi() {
      return {
        projectTopologyDraft: vi.fn(
          (documentId: string, semanticVersion: number) =>
            Promise.resolve({
              status: "ok" as const,
              document_id: documentId,
              semantic_version: semanticVersion,
              topology_projection: projection(`draft-${semanticVersion}`),
              errors: [],
            }),
        ),
      } as unknown as DashboardApi & {
        projectTopologyDraft: ReturnType<typeof vi.fn>;
      };
    }

    it("starts with an empty ready projection", () => {
      expect(doc.projectionStatus).toBe("ready");
      expect(doc.topologyProjection).toEqual(emptyProjection());
      expect(doc.pendingProjectionEntityIds).toEqual([]);
    });

    it("requests a draft projection after a structural edit", async () => {
      const api = draftApi();
      doc.attachApi(api);
      doc.replaceFromLoadedGraph(makeGraph(), emptyProjection());

      doc.addNode(hostNode("first"));

      expect(doc.projectionStatus).toBe("pending");
      await vi.waitFor(() => expect(markerOf()).toBe("draft-2"));
      expect(doc.projectionStatus).toBe("ready");
      expect(api.projectTopologyDraft).toHaveBeenCalledWith(
        doc.id,
        2,
        expect.objectContaining({
          nodes: [expect.objectContaining({ id: "first" })],
        }),
      );
    });

    it("does not request a projection for a geometry-only edit", () => {
      const api = draftApi();
      doc.attachApi(api);
      const node = hostNode("n1", 10, 20);
      doc.replaceFromLoadedGraph(
        makeGraph({ nodes: [node] }),
        projection("rev"),
      );

      doc.graph = {
        ...doc.graph,
        nodes: doc.graph.nodes.map((current) => ({
          ...current,
          view_data: { x_pos: 400, y_pos: 250 },
        })),
      };

      expect(api.projectTopologyDraft).not.toHaveBeenCalled();
      expect(markerOf()).toBe("rev");
      expect(doc.projectionStatus).toBe("ready");
    });

    it("debounces inspector field edits", async () => {
      vi.useFakeTimers();
      const api = draftApi();
      doc.attachApi(api);
      const node = hostNode("n1");
      doc.replaceFromLoadedGraph(
        makeGraph({ nodes: [node] }),
        projection("rev"),
      );
      doc.selectNode(node.id);

      doc.updateSelection({ ...node, data: { name: "changed" } });
      doc.updateSelection({ ...node, data: { name: "changed again" } });

      expect(api.projectTopologyDraft).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(300);
      expect(api.projectTopologyDraft).toHaveBeenCalledTimes(1);
    });

    it("applies the saved projection when no semantic edit happened", async () => {
      doc.replaceFromLoadedGraph(makeGraph(), projection("rev"));
      const api = {
        saveGraph: vi.fn().mockResolvedValue({
          status: "ok",
          graph: makeGraph({ revision_id: "r2" }),
          topology_projection: projection("saved"),
        }),
      } as unknown as DashboardApi;

      await expect(doc.save(api)).resolves.toBe(true);

      expect(markerOf()).toBe("saved");
      expect(doc.projectionStatus).toBe("ready");
    });

    it("does not let a stale saved projection overwrite a newer draft", async () => {
      doc.replaceFromLoadedGraph(makeGraph(), projection("rev"));
      let resolveSave!: (value: unknown) => void;
      const projectTopologyDraft = vi.fn(() => new Promise<never>(() => {}));
      const saveGraph = vi.fn(
        () =>
          new Promise((resolve) => {
            resolveSave = resolve;
          }),
      );
      const api = {
        projectTopologyDraft,
        saveGraph,
      } as unknown as DashboardApi;
      doc.attachApi(api);

      const saving = doc.save(api);
      doc.addNode(hostNode("added"));
      resolveSave({
        status: "ok",
        graph: makeGraph({ revision_id: "r2" }),
        topology_projection: projection("stale-save"),
      });

      await expect(saving).resolves.toBe(true);
      expect(markerOf()).toBe("rev");
      expect(doc.projectionStatus).toBe("pending");
    });

    it("prunes pending projection entities when they are deleted", () => {
      const projectTopologyDraft = vi.fn(() => new Promise<never>(() => {}));
      const api = { projectTopologyDraft } as unknown as DashboardApi;
      doc.attachApi(api);
      doc.replaceFromLoadedGraph(makeGraph(), emptyProjection());

      doc.addNode(hostNode("added"));
      expect(doc.pendingProjectionEntityIds).toContain("added");

      doc.deleteSelection();

      expect(doc.pendingProjectionEntityIds).not.toContain("added");
    });
  });

  describe("startOptimization", () => {
    it("forwards the loaded graph, correlation ID, and parameters", async () => {
      doc.replaceFromLoadedGraph(makeGraph({ id: "g1" }), emptyProjection());
      const api = {
        runOptimization: vi.fn().mockResolvedValue({
          status: "accepted",
          graph_revision_id: "r1",
          correlation_id: "corr-1",
          run_id: "optimization-run-1",
        }),
      } as unknown as DashboardApi;

      await doc.startOptimization(
        api,
        { strategy: "cvss", budget: 3 },
        "corr-1",
      );

      expect(api.runOptimization).toHaveBeenCalledWith("r1", "corr-1", {
        strategy: "cvss",
        budget: 3,
      });
    });

    it("does not call the API for an unloaded graph", async () => {
      const api = { runOptimization: vi.fn() } as unknown as DashboardApi;

      await doc.startOptimization(api, {
        strategy: "cvss",
        budget: 3,
      });

      expect(api.runOptimization).not.toHaveBeenCalled();
    });
  });

  describe("ids are unique", () => {
    it("produces different ids for different instances", () => {
      const doc2 = new EditableGraphDocument();
      expect(doc.id).not.toBe(doc2.id);
    });
  });
});

function makeSaveReply(graph: GraphContract) {
  return { status: "ok" as const, graph };
}

function emptyProjection() {
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
