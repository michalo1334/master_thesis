import { describe, it, expect, beforeEach, vi } from "vitest";
import { WorkspaceModel } from "../WorkspaceModel.svelte";
import type {
  GraphSummary,
  LoadedGraph,
  ExperimentSummary,
} from "../../contract";
import type { EditableGraphDocument } from "../../graph/EditableGraphDocument.svelte";
import type { DashboardApi } from "../../dashboard-api";

function makeGraphSummary(overrides: Partial<GraphSummary> = {}): GraphSummary {
  return {
    id: "g1",
    title: "Topology 1",
    node_count: 3,
    edge_count: 2,
    parent_id: null,
    tags: ["original"],
    ...overrides,
  };
}

function makeLoadedGraph(overrides: Partial<LoadedGraph> = {}): LoadedGraph {
  return {
    id: "g1",
    title: "Graph",
    lock_version: 1,
    parent_id: null,
    tags: ["original"],
    nodes: [],
    edges: [],
    ...overrides,
  };
}

function hostNode(id: string, name = id) {
  return {
    id,
    type: "Host" as const,
    data: { name },
    view_data: { x_pos: 0, y_pos: 0 },
  };
}

function makeExperiment(
  overrides: Partial<ExperimentSummary> = {},
): ExperimentSummary {
  return {
    id: "sim-1",
    graph_id: "g1",
    graph_title: "Topology 1",
    iteration_count: 100,
    runtime_ms: 1000,
    seed: 1,
    run_count: 10,
    started_at: "2026-01-01T00:00:00Z",
    ...overrides,
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

describe("WorkspaceModel", () => {
  let model: WorkspaceModel;

  beforeEach(() => {
    model = new WorkspaceModel();
  });

  describe("initialization", () => {
    it("starts with no documents", () => {
      expect(model.documents.length).toBe(0);
    });

    it("has no selected document", () => {
      expect(model.selectedDocumentId).toBeUndefined();
    });

    it("has no active document", () => {
      expect(model.activeDocument).toBeUndefined();
    });

    it("stores graph summaries", () => {
      const summaries = [makeGraphSummary({ id: "a" })];
      const m = new WorkspaceModel(summaries);
      expect(m.graphSummaries).toBe(summaries);
      expect(m.graphSummaries.length).toBe(1);
    });

    it("defaults to empty summaries array", () => {
      expect(model.graphSummaries).toEqual([]);
    });
  });

  describe("handleCreateDocument", () => {
    it("opens topology picker for graph type", () => {
      model.handleCreateDocument("graph");
      expect(model.topologyPickerOpen).toBe(true);
      expect(model.topologyPickerStatus).toBe("");
    });

    it("no-ops for unknown type", () => {
      model.handleCreateDocument("unknown");
      expect(model.topologyPickerOpen).toBe(false);
    });
  });

  describe("createGraphDocument", () => {
    it("creates a graph document", () => {
      const doc = model.createGraphDocument();
      expect(model.documents.length).toBe(1);
      expect(doc.kind).toBe("graph");
      expect(model.selectedDocumentId).toBe(doc.id);
    });
  });

  describe("closeDocument", () => {
    it("closes a non-active document and keeps selection", () => {
      model.createGraphDocument();
      model.createGraphDocument();
      const firstId = model.documents[0].id;
      const secondId = model.documents[1].id;
      model.closeDocument(firstId);
      expect(model.documents.length).toBe(1);
      expect(model.documents[0].id).toBe(secondId);
      expect(model.selectedDocumentId).toBe(secondId);
    });

    it("selects prior tab when closing active document", () => {
      model.createGraphDocument();
      model.createGraphDocument();
      model.createGraphDocument();
      const docs = model.documents;
      model.closeDocument(docs[2].id);
      expect(model.documents.length).toBe(2);
      expect(model.selectedDocumentId).toBe(docs[1].id);
    });

    it("clears selection when closing last document", () => {
      model.createGraphDocument();
      model.closeDocument(model.documents[0].id);
      expect(model.documents.length).toBe(0);
      expect(model.selectedDocumentId).toBeUndefined();
    });

    it("is a no-op for unknown ids", () => {
      model.createGraphDocument();
      model.closeDocument("nonexistent");
      expect(model.documents.length).toBe(1);
    });
  });

  describe("selectDocument", () => {
    it("changes active document", () => {
      model.createGraphDocument();
      model.createGraphDocument();
      model.selectDocument(model.documents[0].id);
      expect(model.selectedDocumentId).toBe(model.documents[0].id);
    });

    it("marks an optimization report as read", () => {
      const report = model.createPendingOptimizationReport({
        graphId: "g1",
        graphTitle: "Test",
        correlationId: "corr-optimization",
        strategy: "cvss",
        budget: 1,
      });
      report.markUnread();

      model.createGraphDocument();
      model.selectDocument(report.id);

      expect(report.hasUnread).toBe(false);
    });
  });

  describe("openLoadedGraph", () => {
    it("creates a new graph document", async () => {
      const graph = makeLoadedGraph({ id: "g1", title: "My Graph" });
      const noopApi = {} as any;
      const result = await model.openLoadedGraph(graph, noopApi);
      expect(model.documents.length).toBe(1);
      expect(model.documents[0].kind).toBe("graph");
      expect(model.documents[0].title).toBe("My Graph");
      expect(result).toBeDefined();
    });

    it("defaults the initial foothold to the first host", async () => {
      const graph = makeLoadedGraph({
        nodes: [hostNode("host-1", "Gateway"), hostNode("host-2", "API")],
      });

      await model.openLoadedGraph(graph, {} as DashboardApi);

      expect(model.activeFootholdHosts).toEqual([
        { id: "host-1", name: "Gateway" },
        { id: "host-2", name: "API" },
      ]);
      expect(model.simulationParams.initial_foothold_node_id).toBe("host-1");
    });

    it("reuses a blank graph document", async () => {
      const noopApi = {} as any;
      model.createGraphDocument();
      const blankId = model.documents[0].id;
      const graph = makeLoadedGraph({ id: "g2", title: "Reused" });
      const result = await model.openLoadedGraph(graph, noopApi);
      expect(model.documents.length).toBe(1);
      expect(model.documents[0].id).toBe(blankId);
      expect(model.documents[0].title).toBe("Reused");
      expect((result as EditableGraphDocument).loaded).toBe(true);
    });

    it("activates existing loaded document", async () => {
      const noopApi = {} as any;
      await model.openLoadedGraph(
        makeLoadedGraph({ id: "g3", title: "First" }),
        noopApi,
      );
      model.createGraphDocument();
      const blankId = model.selectedDocumentId;
      const result = await model.openLoadedGraph(
        makeLoadedGraph({ id: "g3" }),
        noopApi,
      );
      expect(model.documents.length).toBe(2);
      expect(model.selectedDocumentId).not.toBe(blankId);
      expect(result).toBeUndefined();
    });
  });

  describe("upsertGraphSummary", () => {
    it("adds a loaded graph summary and replaces an existing summary", () => {
      model = new WorkspaceModel([makeGraphSummary({ title: "Stale" })]);

      model.upsertGraphSummary(
        makeLoadedGraph({
          title: "Optimized",
          parent_id: "parent-1",
          tags: ["optimization"],
          nodes: [hostNode("host-1")],
          edges: [],
        }),
      );

      expect(model.graphSummaries).toEqual([
        {
          id: "g1",
          title: "Optimized",
          parent_id: "parent-1",
          tags: ["optimization"],
          node_count: 1,
          edge_count: 0,
        },
      ]);
    });

    it("adds a summary when the loaded graph is new", () => {
      model.upsertGraphSummary(makeLoadedGraph({ id: "g2" }));

      expect(model.graphSummaries).toHaveLength(1);
      expect(model.graphSummaries[0]?.id).toBe("g2");
    });
  });

  describe("createPendingReport", () => {
    it("creates a pending simulation report", () => {
      const report = model.createPendingReport({
        graphId: "g1",
        correlationId: "corr-1",
        graphTitle: "Test",
      });
      expect(report.kind).toBe("simulation-report");
      expect(report.status).toBe("pending");
      expect(report.correlationId).toBe("corr-1");
      expect(report.graphId).toBe("g1");
    });

    it("selects the new report", () => {
      const report = model.createPendingReport({
        graphId: "g1",
        correlationId: "corr-1",
        graphTitle: "Test",
      });
      expect(model.selectedDocumentId).toBe(report.id);
    });

    it("creates distinct reports for separate requests on the same graph", () => {
      const first = model.createPendingReport({
        graphId: "g1",
        correlationId: "corr-1",
        graphTitle: "Test",
      });
      const second = model.createPendingReport({
        graphId: "g1",
        correlationId: "corr-2",
        graphTitle: "Test",
      });
      expect(model.documents.length).toBe(2);
      expect(second.id).not.toBe(first.id);
      expect(first.correlationId).toBe("corr-1");
      expect(second.correlationId).toBe("corr-2");
    });
  });

  describe("createPendingOptimizationReport", () => {
    const info = {
      graphId: "g1",
      graphTitle: "Test",
      correlationId: "corr-optimization",
      strategy: "cvss" as const,
      budget: 1,
    };

    it("selects a newly created report and an existing matching report", () => {
      const report = model.createPendingOptimizationReport(info);
      expect(model.selectedDocumentId).toBe(report.id);

      model.createGraphDocument();

      const existing = model.createPendingOptimizationReport(info);

      expect(existing).toBe(report);
      expect(model.selectedDocumentId).toBe(report.id);
    });
  });

  describe("selectExperiment", () => {
    const api = {
      requestSimulationReport: vi.fn(),
    } as unknown as DashboardApi;

    it("reuses a historical report only when its experiment ID matches", async () => {
      const existing = model.createPendingReport({
        graphId: "g1",
        correlationId: "corr-old",
        graphTitle: "Test",
      });
      existing.markReady("sim-old");

      await model.selectExperiment(api, makeExperiment({ id: "sim-new" }));

      expect(model.documents).toHaveLength(2);

      await model.selectExperiment(api, makeExperiment({ id: "sim-old" }));

      expect(model.documents).toHaveLength(2);
      expect(model.selectedDocumentId).toBe(existing.id);
    });
  });

  describe("showExperiments", () => {
    it("fetches unique IDs from open loaded graph tabs only", async () => {
      model = new WorkspaceModel([
        makeGraphSummary({ id: "g1" }),
        makeGraphSummary({ id: "g2" }),
        makeGraphSummary({ id: "closed" }),
      ]);
      const first = model.createGraphDocument();
      first.replaceFromLoadedGraph(makeLoadedGraph({ id: "g1" }));
      const second = model.createGraphDocument();
      second.replaceFromLoadedGraph(makeLoadedGraph({ id: "g2" }));
      const duplicate = model.createGraphDocument();
      duplicate.replaceFromLoadedGraph(makeLoadedGraph({ id: "g1" }));
      const closed = model.createGraphDocument();
      closed.replaceFromLoadedGraph(makeLoadedGraph({ id: "closed" }));
      model.closeDocument(closed.id);
      const api = {
        fetchExperiments: vi.fn().mockResolvedValue({ experiments: [] }),
      } as unknown as DashboardApi;

      await model.showExperiments(api);

      expect(api.fetchExperiments).toHaveBeenCalledWith(["g1", "g2"]);
    });

    it("shows the empty state without fetching when no loaded graph tabs are open", async () => {
      model = new WorkspaceModel([makeGraphSummary()]);
      const graph = model.createGraphDocument();
      graph.replaceFromLoadedGraph(makeLoadedGraph());
      model.closeDocument(graph.id);
      const api = {
        fetchExperiments: vi.fn(),
      } as unknown as DashboardApi;

      await model.showExperiments(api);

      expect(model.experimentsModalOpen).toBe(true);
      expect(model.experimentsStatus).toBe("No experiments found.");
      expect(api.fetchExperiments).not.toHaveBeenCalled();
    });

    it("ignores duplicate requests while experiments are loading", async () => {
      const graph = model.createGraphDocument();
      graph.replaceFromLoadedGraph(makeLoadedGraph());
      const request = deferred<{ experiments: ExperimentSummary[] }>();
      const api = {
        fetchExperiments: vi.fn().mockReturnValue(request.promise),
      } as unknown as DashboardApi;

      const first = model.showExperiments(api);
      expect(model.isLoadingExperiments).toBe(true);
      const second = model.showExperiments(api);

      expect(api.fetchExperiments).toHaveBeenCalledTimes(1);

      request.resolve({ experiments: [] });
      await Promise.all([first, second]);

      expect(model.isLoadingExperiments).toBe(false);
      expect(model.experimentsStatus).toBe("No experiments found.");
    });

    it("shows a status and resets loading when experiments fail to load", async () => {
      const graph = model.createGraphDocument();
      graph.replaceFromLoadedGraph(makeLoadedGraph());
      const api = {
        fetchExperiments: vi.fn().mockRejectedValue(new Error("offline")),
      } as unknown as DashboardApi;

      await model.showExperiments(api);

      expect(model.isLoadingExperiments).toBe(false);
      expect(model.experimentsStatus).toBe("Failed to load experiments.");
    });
  });

  describe("applyForceLayout", () => {
    it("delegates to active graph synchronously", () => {
      const doc = model.createGraphDocument();
      const originalRev = doc.revision;
      doc.replaceFromLoadedGraph(
        makeLoadedGraph({
          id: "g1",
          nodes: [
            {
              id: "n1",
              type: "Host",
              data: { name: "h1" },
              view_data: { x_pos: 0, y_pos: 0 },
            },
            {
              id: "n2",
              type: "Host",
              data: { name: "h2" },
              view_data: { x_pos: 100, y_pos: 100 },
            },
          ],
          edges: [],
        }),
      );
      const graphBefore = doc.graph;
      model.applyForceLayout();
      // Force layout alters node positions, so the graph reference should change
      expect(doc.graph).not.toBe(graphBefore);
      expect(doc.revision).toBeGreaterThan(originalRev);
    });

    it("no-ops without active graph", () => {
      model.applyForceLayout();
      expect(model.documents.length).toBe(0);
    });
  });
});
