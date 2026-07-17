import { describe, expect, it } from "vitest";
import { createDemoTopologyGraph } from "./demo-graph";
import {
  createSimulationDocument,
  createTopologyDocument,
  type WorkspaceSnapshot,
} from "./model";
import { parseWorkspace, serializeWorkspace } from "./persistence";

function createWorkspace(): WorkspaceSnapshot {
  const topology = createTopologyDocument(
    "topology-1",
    "Production topology",
    createDemoTopologyGraph("topology-1"),
  );
  topology.editor = {
    ...topology.editor,
    tool: "connect",
    selectedId: "topology-1-service-api",
    zoom: 150,
    pan: { x: 120, y: -40 },
  };

  return {
    documents: [
      topology,
      createSimulationDocument("simulation-2", "Simulation result 1"),
    ],
    activeDocumentId: "topology-1",
    nextDocumentId: 3,
  };
}

describe("workspace persistence", () => {
  it("persists complete topology state but excludes simulation documents", () => {
    const restored = parseWorkspace(serializeWorkspace(createWorkspace()));

    expect(restored).toEqual(
      expect.objectContaining({
        activeDocumentId: "topology-1",
        nextDocumentId: 3,
      }),
    );
    expect(restored?.documents).toHaveLength(1);
    expect(restored?.documents[0]).toMatchObject({
      id: "topology-1",
      title: "Production topology",
      type: "topology",
      editor: {
        tool: "connect",
        selectedId: "topology-1-service-api",
        zoom: 100,
        pan: { x: 0, y: 0 },
      },
    });
    expect(
      restored?.documents[0].type === "topology" &&
        restored.documents[0].graph.nodes,
    ).toHaveLength(4);
  });

  it("does not restore the active simulation document", () => {
    const workspace = createWorkspace();
    workspace.activeDocumentId = "simulation-2";

    expect(parseWorkspace(serializeWorkspace(workspace))).toMatchObject({
      activeDocumentId: undefined,
    });
  });

  it("rejects malformed, legacy, and duplicate-document payloads", () => {
    expect(parseWorkspace("not json")).toBeUndefined();
    expect(
      parseWorkspace(
        JSON.stringify({
          documents: [],
          activeDocumentId: undefined,
          nextDocumentId: 1,
        }),
      ),
    ).toBeUndefined();

    const duplicateDocuments = JSON.parse(
      serializeWorkspace(createWorkspace()),
    );
    duplicateDocuments.documents.push(duplicateDocuments.documents[0]);

    expect(parseWorkspace(JSON.stringify(duplicateDocuments))).toBeUndefined();

    const danglingEdge = JSON.parse(serializeWorkspace(createWorkspace()));
    danglingEdge.documents[0].graph.edges[0].fromId = "missing-node";

    expect(parseWorkspace(JSON.stringify(danglingEdge))).toBeUndefined();
  });
});
