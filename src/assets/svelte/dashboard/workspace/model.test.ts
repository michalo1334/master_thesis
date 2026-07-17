import { describe, expect, it } from "vitest";
import { createDemoTopologyGraph } from "./demo-graph";
import {
  createTopologyDocument,
  nextActiveDocumentId,
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
