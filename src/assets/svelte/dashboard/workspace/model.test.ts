import { describe, expect, it, vi } from "vitest";
import { createDemoTopologyGraph } from "./demo-graph";
import {
  applySavedTopology,
  cloneTopologyGraph,
  createNetworkReachabilityEdge,
  createTopologyDocumentFromServerGraph,
  createTopologyDocument,
  nextActiveDocumentId,
  topologyEditableStateKey,
  topologyFromSuccessfulSaveReply,
  topologyGraphFromServerGraph,
  topologySavePayload,
  NETWORK_REACHABILITY_TYPE,
  type ServerTopologyGraph,
  type WorkspaceDocument,
} from "./model";

describe("topology documents", () => {
  it("clones a template graph for every document", () => {
    const template = createDemoTopologyGraph("template");
    template.nodes[0].viewData.color = "blue";
    const first = createTopologyDocument("topology-1", "First", template);
    const second = createTopologyDocument("topology-2", "Second", template);

    first.graph.nodes[0].data.name = "Changed node";
    first.graph.nodes[0].viewData.color = "red";
    first.editor.zoom = 150;

    expect(second.graph.nodes[0].data.name).not.toBe("Changed node");
    expect(second.graph.nodes[0].viewData.color).toBe("blue");
    expect(second.editor.zoom).toBe(100);
  });

  it("uses backend-compatible defaults in the demo graph", () => {
    const graph = createDemoTopologyGraph("graph-1");

    expect(graph.lockVersion).toBe(1);
    expect(
      [...graph.nodes, ...graph.edges].every((element) =>
        element.type.startsWith("Elixir."),
      ),
    ).toBe(true);
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
    lockVersion: 3,
    nodes: [
      {
        id: "node-b",
        graphId: "graph-1",
        type: "NetworkDefense.Nodes.Host",
        data: {},
        viewData: { x_pos: 280, y_pos: 80, collapsed: true },
      },
      {
        id: "node-a",
        graphId: "graph-1",
        type: "NetworkDefense.Nodes.Host",
        data: {},
        viewData: { x_pos: 80, y_pos: 80 },
      },
    ],
    edges: [],
  };

  it("uses node view data from the server graph", () => {
    const graph = topologyGraphFromServerGraph(selectedGraph);

    expect(graph.nodes.map(({ id, viewData }) => ({ id, viewData }))).toEqual([
      {
        id: "node-b",
        viewData: { x_pos: 280, y_pos: 80, collapsed: true },
      },
      { id: "node-a", viewData: { x_pos: 80, y_pos: 80 } },
    ]);
  });

  it("creates a local tab while preserving the server graph id and title", () => {
    const document = createTopologyDocumentFromServerGraph(
      "topology-7",
      selectedGraph,
    );

    expect(document).toMatchObject({
      id: "topology-7",
      title: "Production network",
      graph: {
        id: "graph-1",
        title: "Production network",
        lockVersion: 3,
      },
    });
  });

  it("copies reactive server metadata into the local graph", () => {
    const graph: ServerTopologyGraph = {
      ...selectedGraph,
      nodes: [
        {
          ...selectedGraph.nodes[0],
          data: new Proxy({ name: "Gateway" }, {}),
          viewData: new Proxy({ x_pos: 280, y_pos: 80, color: "blue" }, {}),
        },
      ],
    };

    const document = createTopologyDocumentFromServerGraph("topology-8", graph);

    expect(document.graph.nodes[0].data).toEqual({ name: "Gateway" });
    expect(document.graph.nodes[0].viewData).toEqual({
      x_pos: 280,
      y_pos: 80,
      color: "blue",
    });
  });
});

describe("saved topology application", () => {
  const savedTopology: ServerTopologyGraph = {
    id: "graph-1",
    title: "Production network",
    lockVersion: 4,
    nodes: [
      {
        id: "gateway",
        graphId: "graph-1",
        type: "NetworkDefense.Nodes.Host",
        data: { name: "Updated gateway" },
        viewData: { x_pos: 240, y_pos: 160, color: "orange" },
      },
    ],
    edges: [],
  };

  it("updates only the topology document that initiated the save", () => {
    const first = createTopologyDocument(
      "topology-1",
      "First view",
      createDemoTopologyGraph("graph-1"),
    );
    const second = createTopologyDocument(
      "topology-2",
      "Second view",
      createDemoTopologyGraph("graph-1"),
    );
    second.editor = { ...second.editor, zoom: 150, selectedId: "gateway" };
    const baseline = topologyEditableStateKey(
      topologyGraphFromServerGraph(savedTopology),
    );

    const updated = applySavedTopology(
      [first, second],
      { "topology-1": "stale", "topology-2": "stale" },
      "topology-1",
      savedTopology,
    );

    expect(updated.documents[0]).toMatchObject({
      id: "topology-1",
      title: "Production network",
      graph: {
        title: "Production network",
        lockVersion: 4,
        nodes: [{ id: "gateway" }],
      },
    });
    expect(updated.documents[1]).toBe(second);
    expect(updated.topologyBaselines).toEqual({
      "topology-1": baseline,
      "topology-2": "stale",
    });
  });

  it("keeps edits made while a successful save was in flight", () => {
    const document = createTopologyDocument(
      "topology-1",
      "Production network",
      createDemoTopologyGraph("graph-1"),
    );
    const submittedStateKey = topologyEditableStateKey(document.graph);
    document.graph = {
      ...document.graph,
      title: "Locally renamed network",
    };

    const updated = applySavedTopology(
      [document],
      { "topology-1": "old baseline" },
      document.id,
      savedTopology,
      submittedStateKey,
    );
    const updatedDocument = updated.documents[0];

    expect(updatedDocument).toMatchObject({
      title: "Locally renamed network",
      graph: { title: "Locally renamed network", lockVersion: 4 },
    });
    expect(updated.topologyBaselines[document.id]).toBe(
      topologyEditableStateKey(topologyGraphFromServerGraph(savedTopology)),
    );
  });

  it("preserves unrelated documents and baselines", () => {
    const matching = createTopologyDocument(
      "topology-1",
      "Matching",
      createDemoTopologyGraph("graph-1"),
    );
    const unrelated = createTopologyDocument(
      "topology-2",
      "Unrelated",
      createDemoTopologyGraph("graph-2"),
    );
    const simulation = {
      id: "simulation-3",
      title: "Simulation",
      type: "simulation",
    } as const;

    const updated = applySavedTopology(
      [matching, unrelated, simulation],
      { "topology-1": "stale", "topology-2": "unchanged" },
      "topology-1",
      savedTopology,
    );

    expect(updated.documents[1]).toBe(unrelated);
    expect(updated.documents[2]).toBe(simulation);
    expect(updated.topologyBaselines["topology-2"]).toBe("unchanged");
  });
});

describe("topology editable state", () => {
  it("compares title, nodes, edges, and view data canonically", () => {
    const graph = createDemoTopologyGraph("graph-1");
    graph.nodes[0].data = { z: 1, nested: { z: 2, a: 3 }, a: 4 };
    const equivalent = cloneTopologyGraph(graph);
    equivalent.nodes.reverse();
    equivalent.edges.reverse();
    equivalent.nodes.find((node) => node.id === graph.nodes[0].id)!.data = {
      a: 4,
      nested: { a: 3, z: 2 },
      z: 1,
    };
    equivalent.nodes.find((node) => node.id === graph.nodes[0].id)!.viewData = {
      y_pos: graph.nodes[0].viewData.y_pos,
      label: { z: 2, a: 1 },
      x_pos: graph.nodes[0].viewData.x_pos,
    };
    graph.nodes[0].viewData.label = { a: 1, z: 2 };

    const baseline = topologyEditableStateKey(graph);
    expect(topologyEditableStateKey(equivalent)).toBe(baseline);

    const changedTitle = cloneTopologyGraph(graph);
    changedTitle.title = "Renamed";
    const changedNode = cloneTopologyGraph(graph);
    changedNode.nodes[0].data.name = "Renamed node";
    const changedEdge = cloneTopologyGraph(graph);
    changedEdge.edges[0].data.allowed = false;
    const changedViewData = cloneTopologyGraph(graph);
    changedViewData.nodes[0].viewData.x_pos += 1;

    for (const changed of [
      changedTitle,
      changedNode,
      changedEdge,
      changedViewData,
    ]) {
      expect(topologyEditableStateKey(changed)).not.toBe(baseline);
    }
  });
});

describe("topology saving", () => {
  it("builds a complete full-graph save payload", () => {
    const graph = createDemoTopologyGraph("graph-1");
    graph.title = "Production network";
    graph.lockVersion = 7;

    const payload = topologySavePayload(graph);

    expect(payload).toMatchObject({
      graph_id: "graph-1",
      lock_version: 7,
      title: "Production network",
      nodes: graph.nodes.map((node) => ({
        id: node.id,
        type: node.type,
        data: node.data,
        view_data: node.viewData,
      })),
      edges: graph.edges.map((edge) => ({
        id: edge.id,
        from_id: edge.fromId,
        to_id: edge.toId,
        type: edge.type,
        data: edge.data,
      })),
    });
    expect(payload).not.toHaveProperty("positions");
    expect(payload.nodes[0]).not.toHaveProperty("viewData");
  });

  it("does not accept a topology from stale or error replies", () => {
    const topology: ServerTopologyGraph = {
      id: "graph-1",
      title: "Server title",
      lockVersion: 8,
      nodes: [],
      edges: [],
    };

    expect(topologyFromSuccessfulSaveReply({ topology })).toBe(topology);
    expect(
      topologyFromSuccessfulSaveReply({ status: "stale", topology }),
    ).toBeUndefined();
    expect(
      topologyFromSuccessfulSaveReply({ status: "error", topology }),
    ).toBeUndefined();
    expect(
      topologyFromSuccessfulSaveReply({ status: "conflict", topology }),
    ).toBeUndefined();
    expect(
      topologyFromSuccessfulSaveReply({ ok: false, topology }),
    ).toBeUndefined();
    expect(
      topologyFromSuccessfulSaveReply({ error: "stale", topology }),
    ).toBeUndefined();
  });

  it("creates backend-compatible edges with crypto.randomUUID", () => {
    const id = "123e4567-e89b-42d3-a456-426614174000" as ReturnType<
      typeof crypto.randomUUID
    >;
    const randomUUID = vi.spyOn(crypto, "randomUUID").mockReturnValue(id);

    expect(
      createNetworkReachabilityEdge("graph-1", "source", "target"),
    ).toEqual({
      id,
      graphId: "graph-1",
      fromId: "source",
      toId: "target",
      type: NETWORK_REACHABILITY_TYPE,
      data: {},
    });
    expect(randomUUID).toHaveBeenCalledOnce();
    randomUUID.mockRestore();
  });
});
