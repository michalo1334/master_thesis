import { describe, it, expect, beforeEach } from "vitest";
import { DashboardController } from "../DashboardController.svelte";
import type { LoadedGraph } from "../contract";
import type { CanvasDocument } from "../workspace/CanvasDocument.svelte";

function makeLoadedGraph(overrides: Partial<LoadedGraph> = {}): LoadedGraph {
  return {
    id: "g1",
    title: "Graph",
    lock_version: 1,
    nodes: [],
    edges: [],
    ...overrides,
  };
}

describe("DashboardController", () => {
  let controller: DashboardController;

  beforeEach(() => {
    controller = new DashboardController();
  });

  describe("initialization", () => {
    it("starts with no documents", () => {
      expect(controller.documents.length).toBe(0);
    });

    it("has no selected document", () => {
      expect(controller.selectedDocumentId).toBeUndefined();
    });

    it("has no active document", () => {
      expect(controller.activeDocument).toBeUndefined();
    });
  });

  describe("createDocument", () => {
    it("creates a canvas with default title", () => {
      controller.createDocument("canvas");
      expect(controller.documents.length).toBe(1);
      expect(controller.documents[0].kind).toBe("canvas");
      expect(controller.documents[0].title).toBe("Untitled canvas");
      expect(controller.selectedDocumentId).toBe(controller.documents[0].id);
    });

    it("creates a simulation report with static title", () => {
      controller.createDocument("simulation-report");
      expect(controller.documents.length).toBe(1);
      expect(controller.documents[0].kind).toBe("simulation-report");
      expect(controller.documents[0].title).toBe("Simulation report");
      expect(controller.selectedDocumentId).toBe(controller.documents[0].id);
    });

    it("creates multiple reports with the same static title", () => {
      controller.createDocument("simulation-report");
      controller.createDocument("simulation-report");
      expect(controller.documents.length).toBe(2);
      expect(controller.documents[0].title).toBe("Simulation report");
      expect(controller.documents[1].title).toBe("Simulation report");
    });

    it("creates a blank canvas programmatically (still available)", () => {
      controller.createDocument("canvas");
      const doc = controller.documents[0];
      expect(doc.kind).toBe("canvas");
      expect(
        (doc as CanvasDocument)
          .loaded,
      ).toBe(false);
    });
  });

  describe("closeDocument", () => {
    it("closes a non-active document and keeps selection on active", () => {
      controller.createDocument("canvas");
      controller.createDocument("canvas");
      const firstId = controller.documents[0].id;
      const secondId = controller.documents[1].id;

      controller.closeDocument(firstId);
      expect(controller.documents.length).toBe(1);
      expect(controller.documents[0].id).toBe(secondId);
      expect(controller.selectedDocumentId).toBe(secondId);
    });

    it("selects prior tab when closing active document", () => {
      controller.createDocument("canvas");
      controller.createDocument("canvas");
      controller.createDocument("canvas");
      const docs = controller.documents;

      controller.closeDocument(docs[2].id);
      expect(controller.documents.length).toBe(2);
      expect(controller.selectedDocumentId).toBe(docs[1].id);
    });

    it("selects next tab when closing the first active document", () => {
      controller.createDocument("canvas");
      controller.createDocument("canvas");
      controller.selectDocument(controller.documents[0].id);

      controller.closeDocument(controller.documents[0].id);
      expect(controller.documents.length).toBe(1);
      expect(controller.selectedDocumentId).toBe(controller.documents[0].id);
    });

    it("allows closing the last document", () => {
      controller.createDocument("canvas");
      const onlyId = controller.documents[0].id;
      controller.closeDocument(onlyId);
      expect(controller.documents.length).toBe(0);
      expect(controller.selectedDocumentId).toBeUndefined();
    });

    it("is a no-op for unknown ids", () => {
      controller.createDocument("canvas");
      controller.closeDocument("nonexistent");
      expect(controller.documents.length).toBe(1);
    });

    it("sets selectedDocumentId to undefined when closing the last document", () => {
      controller.createDocument("canvas");
      controller.closeDocument(controller.documents[0].id);
      expect(controller.selectedDocumentId).toBeUndefined();
    });

    it("allows closing a report when it is the only document", () => {
      controller.createDocument("simulation-report");
      const reportId = controller.documents[0].id;

      controller.closeDocument(reportId);
      expect(controller.documents.length).toBe(0);
      expect(controller.selectedDocumentId).toBeUndefined();
    });
  });

  describe("selectDocument", () => {
    it("changes active document", () => {
      controller.createDocument("canvas");
      controller.createDocument("canvas");
      controller.selectDocument(controller.documents[0].id);
      expect(controller.selectedDocumentId).toBe(controller.documents[0].id);
    });
  });

  describe("openLoadedGraph", () => {
    it("creates a new canvas tab from empty state", () => {
      const graph = makeLoadedGraph({ id: "g1", title: "My Graph" });
      const result = controller.openLoadedGraph(graph);

      expect(controller.documents.length).toBe(1);
      const doc = controller.documents[0];
      expect(doc.kind).toBe("canvas");
      expect(doc.title).toBe("My Graph");
      expect(
        (doc as CanvasDocument)
          .loaded,
      ).toBe(true);
      expect(
        (doc as CanvasDocument)
          .loadedGraphId,
      ).toBe("g1");
      expect(result).toBe(doc);
      expect(controller.selectedDocumentId).toBe(doc.id);
    });

    it("creates a new canvas tab when no blank canvas is available", () => {
      // First graph creates a tab (no blank canvas to reuse)
      controller.openLoadedGraph(makeLoadedGraph({ id: "g1", title: "G1" }));
      expect(controller.documents.length).toBe(1);
      // All canvases are now loaded; opening another graph creates a new tab
      const graph = makeLoadedGraph({ id: "g2", title: "My Topology" });
      const result = controller.openLoadedGraph(graph);

      expect(controller.documents.length).toBe(2);
      const loadedDoc = controller.documents[1];
      expect(loadedDoc.kind).toBe("canvas");
      expect(loadedDoc.title).toBe("My Topology");
      expect(
        (
          loadedDoc as CanvasDocument
        ).loaded,
      ).toBe(true);
      expect(
        (
          loadedDoc as CanvasDocument
        ).loadedGraphId,
      ).toBe("g2");
      expect(result).toBe(loadedDoc);
      expect(controller.selectedDocumentId).toBe(loadedDoc.id);
    });

    it("reuses a blank canvas instead of creating a new tab", () => {
      // Programmatically create a blank canvas
      controller.createDocument("canvas");
      const blankId = controller.documents[0].id;
      const graph = makeLoadedGraph({ id: "g2", title: "Reused" });

      const result = controller.openLoadedGraph(graph);

      expect(controller.documents.length).toBe(1); // still 1, blank was reused
      const doc = controller.documents[0];
      expect(doc.id).toBe(blankId);
      expect(doc.title).toBe("Reused");
      expect(
        (doc as CanvasDocument)
          .loaded,
      ).toBe(true);
      expect(result).toBe(doc);
    });

    it("activates existing loaded tab instead of duplicating", () => {
      // Open first graph (creates a new tab from empty state)
      controller.openLoadedGraph(makeLoadedGraph({ id: "g3", title: "First" }));
      // Create a blank canvas (now selected)
      controller.createDocument("canvas");
      const blankId = controller.selectedDocumentId;

      // Open the same graph again — should activate the loaded one, skip blank
      const result = controller.openLoadedGraph(makeLoadedGraph({ id: "g3" }));

      // Still 2 documents (loaded "g3" + blank), loaded one is now selected
      expect(controller.documents.length).toBe(2);
      expect(controller.selectedDocumentId).not.toBe(blankId);
      expect(
        (
          controller
            .documents[0] as CanvasDocument
        ).loadedGraphId,
      ).toBe("g3");
      expect(result).toBeUndefined(); // undefined = activated existing, no new tab
    });

    it("reuses a blank canvas when opening a different graph", () => {
      // Open first graph (creates a new tab from empty state)
      controller.openLoadedGraph(makeLoadedGraph({ id: "g1", title: "G1" }));
      // Create another blank canvas — currently selected
      controller.createDocument("canvas");
      const blankId = controller.selectedDocumentId;
      const g2 = makeLoadedGraph({ id: "g2", title: "G2" });

      // Open g2 — should reuse the blank canvas
      const result = controller.openLoadedGraph(g2);

      expect(controller.documents.length).toBe(2);
      // The blank canvas at blankId should now be loaded with G2
      const reused = controller.documents.find((d) => d.id === blankId)!;
      expect(reused).toBeDefined();
      expect(reused.title).toBe("G2");
      expect(
        (reused as CanvasDocument)
          .loadedGraphId,
      ).toBe("g2");
      expect(result).toBe(reused);
      expect(controller.selectedDocumentId).toBe(reused.id);
    });
  });
});
