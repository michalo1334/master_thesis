import { describe, expect, it } from "vitest";
import { createDemoTopologyGraph } from "./demo-graph";
import {
  createSimulationDocument,
  createTopologyDocument,
  topologyEditableStateKey,
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
    topologyBaselines: {
      "topology-1": topologyEditableStateKey(topology.graph),
    },
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
      graph: {
        title: "Production topology",
        lockVersion: 1,
      },
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

  it("preserves saved and dirty topology state across reloads", () => {
    const savedWorkspace = createWorkspace();
    const savedBaseline = savedWorkspace.topologyBaselines["topology-1"];
    const restoredSaved = parseWorkspace(serializeWorkspace(savedWorkspace));

    expect(restoredSaved?.topologyBaselines["topology-1"]).toBe(savedBaseline);
    expect(
      restoredSaved?.documents[0].type === "topology" &&
        topologyEditableStateKey(restoredSaved.documents[0].graph),
    ).toBe(savedBaseline);

    const dirtyWorkspace = createWorkspace();
    const dirtyDocument = dirtyWorkspace.documents[0];
    if (dirtyDocument.type !== "topology") throw new Error("Topology expected");
    dirtyDocument.graph.title = "Unsaved local title";
    dirtyDocument.title = dirtyDocument.graph.title;

    const restoredDirty = parseWorkspace(serializeWorkspace(dirtyWorkspace));

    expect(restoredDirty?.topologyBaselines["topology-1"]).toBe(
      dirtyWorkspace.topologyBaselines["topology-1"],
    );
    expect(restoredDirty?.documents[0]).toMatchObject({
      title: "Unsaved local title",
      graph: { title: "Unsaved local title" },
    });
    expect(
      restoredDirty?.documents[0].type === "topology" &&
        topologyEditableStateKey(restoredDirty.documents[0].graph),
    ).not.toBe(restoredDirty?.topologyBaselines["topology-1"]);
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

    const legacyWorkspace = JSON.parse(serializeWorkspace(createWorkspace()));
    legacyWorkspace.version = 4;
    expect(parseWorkspace(JSON.stringify(legacyWorkspace))).toBeUndefined();

    const duplicateDocuments = JSON.parse(
      serializeWorkspace(createWorkspace()),
    );
    duplicateDocuments.documents.push(duplicateDocuments.documents[0]);

    expect(parseWorkspace(JSON.stringify(duplicateDocuments))).toBeUndefined();

    const danglingEdge = JSON.parse(serializeWorkspace(createWorkspace()));
    danglingEdge.documents[0].graph.edges[0].fromId = "missing-node";

    expect(parseWorkspace(JSON.stringify(danglingEdge))).toBeUndefined();

    const missingLockVersion = JSON.parse(
      serializeWorkspace(createWorkspace()),
    );
    delete missingLockVersion.documents[0].graph.lockVersion;

    expect(parseWorkspace(JSON.stringify(missingLockVersion))).toBeUndefined();

    const missingBaselines = JSON.parse(serializeWorkspace(createWorkspace()));
    delete missingBaselines.topologyBaselines;

    expect(parseWorkspace(JSON.stringify(missingBaselines))).toBeUndefined();

    const missingDocumentBaseline = JSON.parse(
      serializeWorkspace(createWorkspace()),
    );
    delete missingDocumentBaseline.topologyBaselines["topology-1"];

    expect(
      parseWorkspace(JSON.stringify(missingDocumentBaseline)),
    ).toBeUndefined();
  });
});
