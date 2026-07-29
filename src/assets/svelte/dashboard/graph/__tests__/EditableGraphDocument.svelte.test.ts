import { describe, it, expect, beforeEach, vi } from "vitest";
import { EditableGraphDocument } from "../EditableGraphDocument.svelte";
import type { LoadedGraph } from "../../contract";
import type { DashboardApi } from "../../dashboard-api";

function makeGraph(overrides: Partial<LoadedGraph> = {}): LoadedGraph {
  return {
    id: "g1",
    title: "Graph",
    lock_version: 1,
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

    it("has null loadedGraphId initially", () => {
      expect(doc.loadedGraphId).toBeNull();
    });

    it("has zero lockVersion initially", () => {
      expect(doc.lockVersion).toBe(0);
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
        lock_version: 3,
        nodes: [hostNode("n1", 10, 20)],
      });
      doc.replaceFromLoadedGraph(graph);
      expect(doc.loaded).toBe(true);
      expect(doc.loadedGraphId).toBe("server-g");
      expect(doc.lockVersion).toBe(3);
      expect(doc.title).toBe("Server Topology");
      expect(doc.saveEligible).toBe(true);
    });

    it("replaceFromSaveReply updates graph and lock version", () => {
      doc.replaceFromLoadedGraph(
        makeGraph({ id: "sg", lock_version: 1, title: "V1" }),
      );
      const updated = makeGraph({ id: "sg", title: "V2", lock_version: 2 });
      doc.replaceFromSaveReply(updated);
      expect(doc.lockVersion).toBe(2);
      expect(doc.title).toBe("V2");
    });
  });

  describe("startOptimization", () => {
    it("forwards the loaded graph, correlation ID, and parameters", async () => {
      doc.replaceFromLoadedGraph(makeGraph({ id: "g1" }));
      const api = {
        runOptimization: vi.fn().mockResolvedValue({
          status: "accepted",
          graph_id: "g1",
          correlation_id: "corr-1",
        }),
      } as unknown as DashboardApi;

      await doc.startOptimization(
        api,
        { strategy: "cvss", budget: 3 },
        "corr-1",
      );

      expect(api.runOptimization).toHaveBeenCalledWith("g1", "corr-1", {
        strategy: "cvss",
        budget: 3,
      });
    });

    it("does not call the API for an unloaded graph", async () => {
      const api = { runOptimization: vi.fn() } as unknown as DashboardApi;

      await doc.startOptimization(api, { strategy: "cvss", budget: 3 });

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
