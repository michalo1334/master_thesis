import { describe, it, expect, beforeEach } from "vitest";
import { CanvasDocument } from "../document/CanvasDocument.svelte";
import type { LoadedGraph } from "../contract";

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

describe("CanvasDocument", () => {
  let doc: CanvasDocument;

  beforeEach(() => {
    doc = new CanvasDocument("Test canvas");
  });

  describe("initial state", () => {
    it("has kind canvas", () => {
      expect(doc.kind).toBe("canvas");
    });

    it("has the provided title", () => {
      expect(doc.title).toBe("Test canvas");
    });

    it("has a non-empty id", () => {
      expect(doc.id).toBeTruthy();
      expect(typeof doc.id).toBe("string");
    });

    it("has no selection initially", () => {
      expect(doc.selection.kind).toBe("none");
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

    it("is not save eligible initially (blank canvas)", () => {
      expect(doc.saveEligible).toBe(false);
    });
  });

  describe("selection", () => {
    it("selectNode sets selection to node kind", () => {
      doc.selectNode("node-1");
      expect(doc.selection).toEqual({ kind: "node", nodeId: "node-1" });
    });

    it("selectEdge sets selection to edge kind", () => {
      doc.selectEdge("edge-1");
      expect(doc.selection).toEqual({ kind: "edge", edgeId: "edge-1" });
    });

    it("clearSelection resets to none", () => {
      doc.selectNode("node-1");
      doc.clearSelection();
      expect(doc.selection).toEqual({ kind: "none" });
    });

    it("switches from node to edge selection", () => {
      doc.selectNode("node-1");
      doc.selectEdge("edge-2");
      expect(doc.selection).toEqual({ kind: "edge", edgeId: "edge-2" });
    });

    it("switches from edge to node selection", () => {
      doc.selectEdge("edge-1");
      doc.selectNode("node-2");
      expect(doc.selection).toEqual({ kind: "node", nodeId: "node-2" });
    });
  });

  describe("graph setter preserves valid selection", () => {
    it("retains node selection when the node still exists in the new graph", () => {
      const existingGraph = makeGraph({
        nodes: [
          {
            id: "node-1",
            type: "host",
            data: {},
            view_data: { x_pos: 0, y_pos: 0 },
          },
        ],
      });
      doc.graph = existingGraph;
      doc.selectNode("node-1");

      // replace graph — same node still present
      doc.graph = { ...existingGraph, id: "g2" };

      expect(doc.selection).toEqual({ kind: "node", nodeId: "node-1" });
    });

    it("retains edge selection when the edge still exists in the new graph", () => {
      const existingGraph = makeGraph({
        edges: [
          { id: "edge-1", from_id: "a", to_id: "b", type: "link", data: {} },
        ],
      });
      doc.graph = existingGraph;
      doc.selectEdge("edge-1");

      // replace graph — same edge still present
      doc.graph = { ...existingGraph, id: "g2" };

      expect(doc.selection).toEqual({ kind: "edge", edgeId: "edge-1" });
    });

    it("clears node selection when the node is removed from the new graph", () => {
      const existingGraph = makeGraph({
        nodes: [
          {
            id: "node-1",
            type: "host",
            data: {},
            view_data: { x_pos: 0, y_pos: 0 },
          },
        ],
      });
      doc.graph = existingGraph;
      doc.selectNode("node-1");

      // replace with a graph that does NOT contain node-1
      doc.graph = makeGraph();

      expect(doc.selection.kind).toBe("none");
    });

    it("clears edge selection when the edge is removed from the new graph", () => {
      const existingGraph = makeGraph({
        edges: [
          { id: "edge-1", from_id: "a", to_id: "b", type: "link", data: {} },
        ],
      });
      doc.graph = existingGraph;
      doc.selectEdge("edge-1");

      // replace with a graph that does NOT contain edge-1
      doc.graph = makeGraph();

      expect(doc.selection.kind).toBe("none");
    });

    it("does not clear selection when reading graph", () => {
      doc.selectNode("node-1");
      const _g = doc.graph; // read only, should not clear
      expect(doc.selection.kind).toBe("node");
    });
  });

  describe("loaded graph behavior", () => {
    it("replaceFromLoadedGraph marks the document as loaded", () => {
      const graph = makeGraph({
        id: "server-g",
        title: "Server Topology",
        lock_version: 3,
        nodes: [
          {
            id: "n1",
            type: "router",
            data: {},
            view_data: { x_pos: 10, y_pos: 20 },
          },
        ],
      });

      doc.replaceFromLoadedGraph(graph);

      expect(doc.loaded).toBe(true);
      expect(doc.loadedGraphId).toBe("server-g");
      expect(doc.lockVersion).toBe(3);
      expect(doc.title).toBe("Server Topology");
      expect(doc.graph).toBe(graph);
      expect(doc.saveEligible).toBe(true);
    });

    it("replaceFromLoadedGraph preserves valid node selection", () => {
      doc.selectNode("n1");
      const graph = makeGraph({
        nodes: [
          {
            id: "n1",
            type: "router",
            data: {},
            view_data: { x_pos: 10, y_pos: 20 },
          },
        ],
      });

      doc.replaceFromLoadedGraph(graph);

      expect(doc.selection).toEqual({ kind: "node", nodeId: "n1" });
    });

    it("replaceFromLoadedGraph clears selection when the selected item is gone", () => {
      doc.selectNode("stale-node");
      const graph = makeGraph({
        nodes: [
          {
            id: "n1",
            type: "router",
            data: {},
            view_data: { x_pos: 10, y_pos: 20 },
          },
        ],
      });

      doc.replaceFromLoadedGraph(graph);

      expect(doc.selection.kind).toBe("none");
    });

    it("replaceFromSaveReply updates graph and lock version", () => {
      // First load the document
      doc.replaceFromLoadedGraph(
        makeGraph({ id: "sg", lock_version: 1, title: "V1" }),
      );

      // Simulate successful save reply
      const updatedGraph = makeGraph({
        id: "sg",
        title: "V2",
        lock_version: 2,
      });
      doc.replaceFromSaveReply(updatedGraph);

      expect(doc.lockVersion).toBe(2);
      expect(doc.title).toBe("V2");
      expect(doc.graph).toBe(updatedGraph);
      expect(doc.loaded).toBe(true); // stays loaded
      expect(doc.loadedGraphId).toBe("sg"); // unchanged
    });

    it("replaceFromSaveReply preserves valid selection", () => {
      doc.replaceFromLoadedGraph(
        makeGraph({
          id: "sg",
          lock_version: 1,
          nodes: [
            {
              id: "n1",
              type: "host",
              data: {},
              view_data: { x_pos: 0, y_pos: 0 },
            },
          ],
        }),
      );
      doc.selectNode("n1");

      doc.replaceFromSaveReply(
        makeGraph({
          id: "sg",
          lock_version: 2,
          nodes: [
            {
              id: "n1",
              type: "host",
              data: {},
              view_data: { x_pos: 0, y_pos: 0 },
            },
            {
              id: "n2",
              type: "host",
              data: {},
              view_data: { x_pos: 10, y_pos: 10 },
            },
          ],
        }),
      );

      expect(doc.selection).toEqual({ kind: "node", nodeId: "n1" });
    });
  });

  describe("ids are unique", () => {
    it("produces different ids for different instances", () => {
      const doc2 = new CanvasDocument("Other");
      expect(doc.id).not.toBe(doc2.id);
    });
  });
});
