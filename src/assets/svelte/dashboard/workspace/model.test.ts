import { describe, expect, it } from "vitest";
import { createDemoTopologyGraph } from "./demo-graph";
import {
  createGridPositions,
  createTopologyDocumentFromServerGraph,
  createTopologyDocument,
  nextActiveDocumentId,
  topologyGraphFromServerGraph,
  type ServerTopologyGraph,
  type WorkspaceDocument,
} from "./model";

describe("topology documents", () => {
  it("clones a template graph for every document", () => {
    const template = createDemoTopologyGraph("template");
    const first = createTopologyDocument("topology-1", "First", template);
    const second = createTopologyDocument("topology-2", "Second", template);

    first.graph.nodes[0].data.name = "Changed node";
    first.editor.zoom = 150;

    expect(second.graph.nodes[0].data.name).not.toBe("Changed node");
    expect(second.editor.zoom).toBe(100);
  });
});

describe("nextActiveDocumentId", () => {
  const documents: WorkspaceDocument[] = [
    createTopologyDocument(
      "topology-1",
      "First",
      createDemoTopologyGraph("topology-1"),
    ),
    createTopologyDocument(
      "topology-2",
      "Second",
      createDemoTopologyGraph("topology-2"),
    ),
    { id: "simulation-3", title: "Simulation", type: "simulation" },
  ];

  it("activates the following document when closing the active tab", () => {
    expect(nextActiveDocumentId(documents, "topology-2", "topology-2")).toBe(
      "simulation-3",
    );
  });

  it("activates the preceding document when closing the final active tab", () => {
    expect(
      nextActiveDocumentId(documents, "simulation-3", "simulation-3"),
    ).toBe("topology-2");
  });

  it("keeps the active tab when another document closes", () => {
    expect(nextActiveDocumentId(documents, "topology-1", "simulation-3")).toBe(
      "topology-1",
    );
  });
});

describe("server topology conversion", () => {
  const selectedGraph: ServerTopologyGraph = {
    id: "graph-1",
    title: "Production network",
    nodes: [
      {
        id: "node-b",
        graphId: "graph-1",
        type: "NetworkDefense.Nodes.Host",
        data: {},
      },
      {
        id: "node-a",
        graphId: "graph-1",
        type: "NetworkDefense.Nodes.Host",
        data: {},
      },
    ],
    edges: [],
  };

  it("adds deterministic, non-overlapping positions to a server graph", () => {
    const graph = topologyGraphFromServerGraph(selectedGraph);

    expect(graph.positions).toEqual({
      "node-a": { x: 80, y: 80 },
      "node-b": { x: 280, y: 80 },
    });
  });

  it("assigns positions independently of the server node order", () => {
    expect(createGridPositions(selectedGraph.nodes)).toEqual(
      createGridPositions([...selectedGraph.nodes].reverse()),
    );
  });

  it("keeps every grid position distinct", () => {
    const positions = createGridPositions(
      Array.from({ length: 5 }, (_, index) => ({ id: `node-${index}` })),
    );

    expect([
      ...new Set(Object.values(positions).map(({ x, y }) => `${x},${y}`)),
    ]).toHaveLength(5);
  });

  it("creates a local tab while preserving the server graph id and title", () => {
    const document = createTopologyDocumentFromServerGraph(
      "topology-7",
      selectedGraph,
    );

    expect(document).toMatchObject({
      id: "topology-7",
      title: "Production network",
      graph: { id: "graph-1" },
    });
  });

  it("copies reactive server metadata into the local graph", () => {
    const graph: ServerTopologyGraph = {
      ...selectedGraph,
      nodes: [
        {
          ...selectedGraph.nodes[0],
          data: new Proxy({ name: "Gateway" }, {}),
        },
      ],
    };

    const document = createTopologyDocumentFromServerGraph("topology-8", graph);

    expect(document.graph.nodes[0].data).toEqual({ name: "Gateway" });
  });
});
