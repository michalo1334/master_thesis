import type { GraphContract } from "../../../contracts.generated/graph";
import { describe, it, expect, beforeEach, vi } from "vitest";
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

    it("starts with revision 0", () => {
      expect(doc.revision).toBe(0);
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
      doc.replaceFromLoadedGraph(graph);
      expect(doc.loaded).toBe(true);
      expect(doc.loadedRevisionId).toBe("r3");
      expect(doc.title).toBe("Server Topology");
      expect(doc.saveEligible).toBe(true);
    });

    it("updates the title and marks the graph dirty", () => {
      doc.replaceFromLoadedGraph(makeGraph({ title: "Original" }));

      doc.setTitle("  Renamed graph  ");

      expect(doc.title).toBe("Renamed graph");
      expect(doc.graph.title).toBe("Renamed graph");
      expect(doc.isDirty).toBe(true);
    });

    it("replaceFromSaveReply updates graph and revision", () => {
      doc.replaceFromLoadedGraph(
        makeGraph({ id: "sg", revision_id: "r1", title: "V1" }),
      );
      const updated = makeGraph({ id: "sg", title: "V2", revision_id: "r2" });
      doc.replaceFromSaveReply(updated);
      expect(doc.loadedRevisionId).toBe("r2");
      expect(doc.title).toBe("V2");
    });
  });

  describe("saving", () => {
    it("skips clean graphs when saving if dirty", async () => {
      doc.replaceFromLoadedGraph(makeGraph());
      const api = { saveGraph: vi.fn() } as unknown as DashboardApi;

      await expect(doc.saveIfDirty(api)).resolves.toBe(true);
      expect(api.saveGraph).not.toHaveBeenCalled();
    });

    it("reports manual save success and failure", async () => {
      doc.replaceFromLoadedGraph(makeGraph());
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

    it("saves a changed title in the graph payload", async () => {
      doc.replaceFromLoadedGraph(makeGraph({ title: "Original" }));
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
      doc.replaceFromLoadedGraph(makeGraph());
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

  describe("startOptimization", () => {
    it("forwards the loaded graph, correlation ID, and parameters", async () => {
      doc.replaceFromLoadedGraph(makeGraph({ id: "g1" }));
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
