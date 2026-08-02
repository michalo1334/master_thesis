import { describe, it, expect, beforeEach, vi } from "vitest";
import { WorkspaceModel } from "../WorkspaceModel.svelte";
import type {
  GraphSummary,
  GraphDiffResult,
  LoadedGraph,
  ExperimentSummary,
} from "../../contract";
import type { EditableGraphDocument } from "../../graph/EditableGraphDocument.svelte";
import type { DashboardApi } from "../../dashboard-api";

function makeGraphSummary(overrides: Partial<GraphSummary> = {}): GraphSummary {
  return {
    graph_id: "g1",
    title: "Topology 1",
    node_count: 3,
    edge_count: 2,
    revision_id: "r1",
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    is_favorite: false,
    ...overrides,
  };
}

function makeLoadedGraph(overrides: Partial<LoadedGraph> = {}): LoadedGraph {
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
    graph_revision_id: "r1",
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
      const summaries = [makeGraphSummary({ revision_id: "a" })];
      const m = new WorkspaceModel(summaries);
      expect(m.graphSummaries).toBe(summaries);
      expect(m.graphSummaries.length).toBe(1);
    });

    it("defaults to empty summaries array", () => {
      expect(model.graphSummaries).toEqual([]);
    });

    it("stores folders", () => {
      const folders = [{ id: "folder-1", name: "Threat models" }];
      const workspace = new WorkspaceModel([], folders);
      expect(workspace.folders).toBe(folders);
    });
  });

  describe("folders", () => {
    it("creates a folder after the server accepts it", async () => {
      const api = {
        createFolder: vi.fn().mockResolvedValue({
          status: "ok",
          folder: { id: "folder-1", name: "Threat models" },
        }),
      } as unknown as DashboardApi;

      await expect(model.createFolder(api, " Threat models ")).resolves.toBe(
        true,
      );
      expect(api.createFolder).toHaveBeenCalledWith("Threat models");
      expect(model.folders).toEqual([
        { id: "folder-1", name: "Threat models" },
      ]);
    });

    it("moves every revision of a graph and preserves its folder on upsert", async () => {
      model = new WorkspaceModel([
        makeGraphSummary({ revision_id: "r1" }),
        makeGraphSummary({ revision_id: "r2" }),
      ]);
      const api = {
        moveGraphToFolder: vi.fn().mockResolvedValue({ status: "ok" }),
      } as unknown as DashboardApi;

      await expect(
        model.moveGraphToFolder(api, "g1", "folder-1"),
      ).resolves.toBe(true);
      model.upsertGraphSummary(makeLoadedGraph({ revision_id: "r3" }));

      expect(api.moveGraphToFolder).toHaveBeenCalledWith("g1", "folder-1");
      expect(model.graphSummaries.map((summary) => summary.folder_id)).toEqual([
        "folder-1",
        "folder-1",
        "folder-1",
      ]);
    });

    it("removes a deleted folder and returns its graphs to the root", async () => {
      model = new WorkspaceModel(
        [makeGraphSummary({ folder_id: "folder-1" })],
        [{ id: "folder-1", name: "Threat models" }],
      );
      const api = {
        deleteFolder: vi.fn().mockResolvedValue({ status: "ok" }),
      } as unknown as DashboardApi;

      await expect(model.deleteFolder(api, "folder-1")).resolves.toBe(true);

      expect(model.folders).toEqual([]);
      expect(model.graphSummaries[0]?.folder_id).toBeNull();
    });

    it("reports concise folder errors", async () => {
      const api = {
        moveGraphToFolder: vi.fn().mockResolvedValue({ status: "not_found" }),
      } as unknown as DashboardApi;

      await expect(model.moveGraphToFolder(api, "g1", null)).resolves.toBe(
        false,
      );
      expect(model.statusMessage).toBe("Could not move graph.");
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
        graphRevisionId: "r1",
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

  describe("openGraphRevision", () => {
    it("opens the requested revision", async () => {
      const api = {
        openGraph: vi.fn().mockResolvedValue({
          status: "ok",
          graph: makeLoadedGraph({ revision_id: "simulated-r1" }),
        }),
      } as unknown as DashboardApi;

      await expect(model.openGraphRevision(api, "simulated-r1")).resolves.toBe(
        true,
      );

      expect(api.openGraph).toHaveBeenCalledWith("simulated-r1");
      expect(model.activeGraph?.loadedRevisionId).toBe("simulated-r1");
    });

    it("opens a clean copy when the same revision has unsaved edits", async () => {
      const original = makeLoadedGraph({
        title: "Persisted",
        revision_id: "simulated-r1",
      });
      await model.openLoadedGraph(original, {} as DashboardApi);
      model.activeGraph!.setTitle("Unsaved edit");
      const api = {
        openGraph: vi.fn().mockResolvedValue({ status: "ok", graph: original }),
      } as unknown as DashboardApi;

      await expect(model.openGraphRevision(api, "simulated-r1")).resolves.toBe(
        true,
      );

      expect(model.documents).toHaveLength(2);
      expect(model.activeGraph?.title).toBe("Persisted");
      expect(model.activeGraph?.isDirty).toBe(false);
    });
  });

  describe("graph comparison", () => {
    const baseSummary = makeGraphSummary({
      graph_id: "base",
      revision_id: "base-r1",
      title: "Base",
    });
    const comparisonSummary = makeGraphSummary({
      graph_id: "comparison",
      revision_id: "comparison-r1",
      title: "Comparison",
    });
    const graphs = {
      base: makeLoadedGraph({
        id: "base",
        revision_id: "base-r1",
        title: "Base",
      }),
      comparison: makeLoadedGraph({
        id: "comparison",
        revision_id: "comparison-r1",
        title: "Comparison",
      }),
    };
    const serverResult: GraphDiffResult = {
      graph: makeLoadedGraph({
        id: "merged",
        title: "Server merged graph",
        nodes: [hostNode("server-node")],
      }),
      node_status: [{ id: "server-node", status: "removed" }],
      edge_status: [{ id: "server-edge", status: "added" }],
      node_counts: { added: 1, removed: 2, unchanged: 3 },
      edge_counts: { added: 4, removed: 5, unchanged: 6 },
    };

    it("stages selection and renders server comparison statuses", async () => {
      const api = {
        openGraph: vi.fn((revisionId: string) =>
          Promise.resolve({
            status: "ok" as const,
            graph: revisionId === "base-r1" ? graphs.base : graphs.comparison,
          }),
        ),
        compareGraphs: vi.fn().mockResolvedValue({
          status: "ok",
          result: serverResult,
        }),
      } as unknown as DashboardApi;

      model.beginGraphComparison();
      expect(model.graphComparisonPickerOpen).toBe(true);
      expect(model.graphComparisonPickerTitle).toBe("Compare graphs");

      await expect(
        model.selectGraphForComparison(api, baseSummary),
      ).resolves.toBe(false);
      expect(model.graphComparisonPickerTitle).toBe("Compare with graph");
      expect(model.graphComparisonPickerDescription).toContain("Base");

      await expect(
        model.selectGraphForComparison(api, baseSummary),
      ).resolves.toBe(false);
      expect(model.graphComparisonPickerStatus).toBe(
        "Select a different graph.",
      );

      await expect(
        model.selectGraphForComparison(api, comparisonSummary),
      ).resolves.toBe(true);
      const first = model.activeDocument;
      expect(first?.kind).toBe("graph-diff");
      expect(model.graphComparisonPickerOpen).toBe(false);
      expect(api.openGraph).toHaveBeenCalledWith("base-r1");
      expect(api.openGraph).not.toHaveBeenCalledWith("comparison-r1");
      expect(api.compareGraphs).toHaveBeenCalledWith(
        "base-r1",
        "comparison-r1",
      );
      if (!first || first.kind !== "graph-diff")
        throw new Error("Expected graph diff");
      expect(first.graph).toBe(serverResult.graph);
      expect(first.nodeStatusById.get("server-node")).toBe("removed");
      expect(first.edgeStatusById.get("server-edge")).toBe("added");
      expect(first.nodeCounts).toEqual(serverResult.node_counts);
      expect(first.edgeCounts).toEqual(serverResult.edge_counts);

      model.beginGraphComparison();
      await model.selectGraphForComparison(api, baseSummary);
      await model.selectGraphForComparison(api, comparisonSummary);

      expect(model.documents).toHaveLength(2);
      expect(model.selectedDocumentId).not.toBe(first?.id);
    });

    it("loads an optimization graph diff without opening another document", async () => {
      const api = {
        openGraph: vi.fn().mockResolvedValue({
          status: "ok",
          graph: graphs.base,
        }),
        compareGraphs: vi.fn().mockResolvedValue({
          status: "ok",
          result: serverResult,
        }),
      } as unknown as DashboardApi;

      const result = await model.loadOptimizationGraphDiff(
        api,
        "base-r1",
        "optimized-r1",
      );

      expect(result?.title).toBe("Base compared with Optimized graph");
      expect(result?.graph).toBe(serverResult.graph);
      expect(model.documents).toHaveLength(0);
      expect(api.openGraph).toHaveBeenCalledWith("base-r1");
      expect(api.compareGraphs).toHaveBeenCalledWith("base-r1", "optimized-r1");
    });

    it("keeps the base staged when the server cannot produce a comparison", async () => {
      const api = {
        openGraph: vi
          .fn()
          .mockResolvedValue({ status: "ok", graph: graphs.base }),
        compareGraphs: vi.fn().mockResolvedValue({
          status: "not_found",
          result: null,
        }),
      } as unknown as DashboardApi;

      model.beginGraphComparison();
      await model.selectGraphForComparison(api, baseSummary);

      await expect(
        model.selectGraphForComparison(api, comparisonSummary),
      ).resolves.toBe(false);
      expect(model.graphComparisonPickerOpen).toBe(true);
      expect(model.graphComparisonBase).toBe(graphs.base);
      expect(model.graphComparisonPickerStatus).toBe(
        "Comparison graph not found.",
      );
      expect(api.openGraph).not.toHaveBeenCalledWith("comparison-r1");
    });

    it("keeps the base staged when an ok comparison has no result", async () => {
      const api = {
        openGraph: vi
          .fn()
          .mockResolvedValue({ status: "ok", graph: graphs.base }),
        compareGraphs: vi.fn().mockResolvedValue({
          status: "ok",
          result: null,
        }),
      } as unknown as DashboardApi;

      model.beginGraphComparison();
      await model.selectGraphForComparison(api, baseSummary);

      await expect(
        model.selectGraphForComparison(api, comparisonSummary),
      ).resolves.toBe(false);
      expect(model.graphComparisonPickerStatus).toBe(
        "Failed to compare graphs.",
      );
      expect(model.documents).toHaveLength(0);
    });

    it("requires saving the active graph before comparing revisions", () => {
      const document = model.createGraphDocument();
      document.replaceFromLoadedGraph(graphs.base);
      document.addNode(hostNode("unsaved", "Unsaved host"));

      model.beginGraphComparisonWithActive(document);

      expect(model.graphComparisonPickerOpen).toBe(false);
      expect(model.statusMessage).toBe("Save the graph before comparing it.");
    });
  });

  describe("upsertGraphSummary", () => {
    it("adds a summary for each persisted revision", () => {
      model = new WorkspaceModel([makeGraphSummary({ title: "Stale" })]);

      model.upsertGraphSummary(
        makeLoadedGraph({
          title: "Optimized",
          parent_revision_id: "parent-r1",
          revision_id: "r2",
          revision_kind: "optimization",
          revision_number: 2,
          nodes: [hostNode("host-1")],
          edges: [],
        }),
      );

      expect(model.graphSummaries).toEqual([
        makeGraphSummary({ title: "Stale" }),
        {
          graph_id: "g1",
          title: "Optimized",
          revision_id: "r2",
          parent_revision_id: "parent-r1",
          revision_kind: "optimization",
          revision_number: 2,
          node_count: 1,
          edge_count: 0,
          is_favorite: false,
        },
      ]);
    });

    it("adds a summary when the loaded graph is new", () => {
      model.upsertGraphSummary(makeLoadedGraph({ id: "g2" }));

      expect(model.graphSummaries).toHaveLength(1);
      expect(model.graphSummaries[0]?.graph_id).toBe("g2");
    });
  });

  describe("setGraphRevisionFavorite", () => {
    it("updates the matching summary after the server accepts the change", async () => {
      model = new WorkspaceModel([makeGraphSummary()]);
      const api = {
        setGraphRevisionFavorite: vi
          .fn()
          .mockResolvedValue({ status: "ok", favorite: true }),
      } as unknown as DashboardApi;

      await expect(
        model.setGraphRevisionFavorite(api, model.graphSummaries[0]!, true),
      ).resolves.toBe(true);

      expect(api.setGraphRevisionFavorite).toHaveBeenCalledWith("r1", true);
      expect(model.graphSummaries[0]?.is_favorite).toBe(true);
    });

    it("keeps summaries unchanged when the server rejects the change", async () => {
      model = new WorkspaceModel([makeGraphSummary()]);
      const api = {
        setGraphRevisionFavorite: vi
          .fn()
          .mockResolvedValue({ status: "not_found", favorite: false }),
      } as unknown as DashboardApi;

      await expect(
        model.setGraphRevisionFavorite(api, model.graphSummaries[0]!, true),
      ).resolves.toBe(false);

      expect(model.graphSummaries[0]?.is_favorite).toBe(false);
      expect(model.topologyPickerStatus).toBe("Graph not found.");
    });
  });

  describe("createPendingReport", () => {
    it("creates a pending simulation report", () => {
      const report = model.createPendingReport({
        graphId: "g1",
        graphRevisionId: "r1",
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
        graphRevisionId: "r1",
        correlationId: "corr-1",
        graphTitle: "Test",
      });
      expect(model.selectedDocumentId).toBe(report.id);
    });

    it("creates distinct reports for separate requests on the same graph", () => {
      const first = model.createPendingReport({
        graphId: "g1",
        graphRevisionId: "r1",
        correlationId: "corr-1",
        graphTitle: "Test",
      });
      const second = model.createPendingReport({
        graphId: "g1",
        graphRevisionId: "r1",
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
      graphRevisionId: "r1",
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
        graphRevisionId: "r1",
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

  describe("openOptimizationRun", () => {
    it("opens and reuses a persisted optimization report", () => {
      const api = {
        requestOptimizationReport: vi.fn(),
      } as unknown as DashboardApi;
      const run = {
        id: "optimization-1",
        graph_id: "g1",
        graph_revision_id: "r1",
        graph_title: "Topology 1",
        strategy: "cvss",
        requested_budget: 2,
        used_budget: 1,
        runtime_ms: 100,
        output_graph_revision_id: "optimized-r1",
        started_at: "2026-01-01T00:00:00Z",
      };

      model.openOptimizationRun(api, run);
      const report = model.activeDocument;
      model.createGraphDocument();
      model.openOptimizationRun(api, run);

      expect(
        model.documents.filter((d) => d.kind === "optimization-report"),
      ).toHaveLength(1);
      expect(model.selectedDocumentId).toBe(report?.id);
      expect(api.requestOptimizationReport).toHaveBeenCalledWith(
        "optimization-1",
        "r1",
      );
    });
  });

  describe("showExperiments", () => {
    it("fetches saved results for every known graph revision", async () => {
      model = new WorkspaceModel([
        makeGraphSummary({ graph_id: "g1", revision_id: "r1" }),
        makeGraphSummary({ graph_id: "g2", revision_id: "r2" }),
        makeGraphSummary({ graph_id: "closed", revision_id: "r3" }),
      ]);
      const first = model.createGraphDocument();
      first.replaceFromLoadedGraph(
        makeLoadedGraph({ id: "g1", revision_id: "r1" }),
      );
      const second = model.createGraphDocument();
      second.replaceFromLoadedGraph(
        makeLoadedGraph({ id: "g2", revision_id: "r2" }),
      );
      const duplicate = model.createGraphDocument();
      duplicate.replaceFromLoadedGraph(
        makeLoadedGraph({ id: "g1", revision_id: "r1" }),
      );
      const closed = model.createGraphDocument();
      closed.replaceFromLoadedGraph(
        makeLoadedGraph({ id: "closed", revision_id: "r3" }),
      );
      model.closeDocument(closed.id);
      const api = {
        fetchExperiments: vi.fn().mockResolvedValue({ experiments: [] }),
        fetchOptimizationRuns: vi.fn().mockResolvedValue({ runs: [] }),
      } as unknown as DashboardApi;

      await model.showExperiments(api);

      expect(api.fetchExperiments).toHaveBeenCalledWith(["r1", "r2", "r3"]);
      expect(api.fetchOptimizationRuns).toHaveBeenCalledWith([
        "r1",
        "r2",
        "r3",
      ]);
    });

    it("shows the empty state without fetching when no graph revisions are known", async () => {
      const api = {
        fetchExperiments: vi.fn(),
        fetchOptimizationRuns: vi.fn(),
      } as unknown as DashboardApi;

      await model.showExperiments(api);

      expect(model.experimentsModalOpen).toBe(true);
      expect(model.experimentsStatus).toBe("No experiments found.");
      expect(api.fetchExperiments).not.toHaveBeenCalled();
      expect(api.fetchOptimizationRuns).not.toHaveBeenCalled();
    });

    it("queues one refresh requested while experiments are loading", async () => {
      model = new WorkspaceModel([makeGraphSummary()]);
      const request = deferred<{ experiments: ExperimentSummary[] }>();
      const optimizationRequest = deferred<{ runs: [] }>();
      const api = {
        fetchExperiments: vi
          .fn()
          .mockReturnValueOnce(request.promise)
          .mockResolvedValue({
            experiments: [makeExperiment({ id: "sim-2" })],
          }),
        fetchOptimizationRuns: vi
          .fn()
          .mockReturnValueOnce(optimizationRequest.promise)
          .mockResolvedValue({ runs: [] }),
      } as unknown as DashboardApi;

      const first = model.loadSavedResults(api);
      expect(model.isLoadingExperiments).toBe(true);
      const completionRefresh = model.loadSavedResults(api);
      const duplicateCompletionRefresh = model.loadSavedResults(api);

      expect(api.fetchExperiments).toHaveBeenCalledTimes(1);

      request.resolve({ experiments: [] });
      optimizationRequest.resolve({ runs: [] });
      await Promise.all([first, completionRefresh, duplicateCompletionRefresh]);

      expect(api.fetchExperiments).toHaveBeenCalledTimes(2);
      expect(api.fetchOptimizationRuns).toHaveBeenCalledTimes(2);
      expect(model.isLoadingExperiments).toBe(false);
      expect(model.experiments).toEqual([makeExperiment({ id: "sim-2" })]);
    });

    it("shows a status and resets loading when experiments fail to load", async () => {
      model = new WorkspaceModel([makeGraphSummary()]);
      const api = {
        fetchExperiments: vi.fn().mockRejectedValue(new Error("offline")),
        fetchOptimizationRuns: vi.fn().mockResolvedValue({ runs: [] }),
      } as unknown as DashboardApi;

      await model.showExperiments(api);

      expect(model.isLoadingExperiments).toBe(false);
      expect(model.experimentsStatus).toBe("Failed to load saved results.");
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
