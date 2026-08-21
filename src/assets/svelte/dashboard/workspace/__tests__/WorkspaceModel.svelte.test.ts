import { describe, it, expect, beforeEach, vi } from "vitest";
import { WorkspaceModel } from "../WorkspaceModel.svelte";
import type {
  GraphSummary,
  GraphDiffResult,
  LoadedGraph,
} from "../../contract";
import type { EditableGraphDocument } from "../../graph/EditableGraphDocument.svelte";
import type { DashboardApi } from "../../dashboard-api";
import type { DocumentCatalogItem } from "../../contract";
import { SimulationReportDocument } from "../../simulation-report/SimulationReportDocument.svelte";
import { createWorkspaceEnvelope } from "../../../ui-kit/workspace/workspace-persistence";

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

    it("does not keep an optimization objective", () => {
      expect(model.optimizationParams).not.toHaveProperty("objective");
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

  describe("persistence restoration", () => {
    it("restores durable stubs and loads them only when activated", async () => {
      const persistence = createWorkspaceEnvelope(
        {
          state: {
            forceParams: {
              repulsion: -100,
              linkDistance: 120,
              collisionRadius: 40,
              centerStrength: 0.1,
              alphaDecay: 0.03,
            },
            simulationParams: {
              initial_foothold_node_id: "host-1",
              monte_carlo_trials: 10,
              iterations_per_run: 20,
              max_attempts: 1,
              generate_seed: false,
              seed: 0,
            },
            optimizationParams: {
              strategy: "cvss" as const,
              budget: 2,
              simulation_params: {
                initial_foothold_node_id: "host-1",
                monte_carlo_trials: 10,
                iterations_per_run: 20,
                max_attempts: 1,
                generate_seed: false,
                seed: 0,
              },
            },
          },
          documents: [
            {
              kind: "graph",
              ids: { revisionId: "r1" },
              title: "Topology",
            },
            {
              kind: "simulation-report",
              ids: {
                experimentId: "experiment-1",
                graphId: "g1",
                graphRevisionId: "r1",
              },
              title: "Report for Topology",
            },
            { kind: "runs", ids: {}, title: "Runs" },
          ],
          selectedDocumentKey:
            "simulation-report:experimentId:experiment-1,graphId:g1,graphRevisionId:r1",
        },
        1,
      );
      const api = {
        openGraph: vi.fn().mockResolvedValue({
          status: "ok",
          graph: makeLoadedGraph(),
        }),
        requestSimulationReport: vi.fn(),
      } as unknown as DashboardApi;

      model = new WorkspaceModel([], [], api);
      model.restorePersistence(persistence);
      const [graph, report, runs] = model.documents;

      expect(model.selectedDocumentId).toBe(report?.id);
      expect(model.forceParams.repulsion).toBe(-100);
      expect(api.openGraph).not.toHaveBeenCalled();
      expect(api.requestSimulationReport).toHaveBeenCalledWith(
        report!.id,
        "experiment-1",
      );

      model.selectDocument(graph!.id);
      expect(api.openGraph).toHaveBeenCalledWith("r1");
      await vi.waitFor(() =>
        expect(model.activeGraph?.loadedRevisionId).toBe("r1"),
      );

      model.selectDocument(runs!.id);
      expect(model.activeDocument?.kind).toBe("runs");
      expect(model.toPersistence()?.documents).toContainEqual({
        kind: "runs",
        ids: {},
        title: "Runs",
      });
      expect(model.toPersistence()?.selectedDocumentKey).toBe("runs:");
    });

    it("does not persist unsaved graphs", () => {
      const unsaved = model.createGraphDocument();
      const saved = model.createGraphDocument();
      saved.replaceFromLoadedGraph(makeLoadedGraph());
      saved.setTitle("Unsaved change");

      expect(model.toPersistence()?.documents).not.toContainEqual(
        expect.objectContaining({ kind: "graph" }),
      );
      expect(unsaved.loaded).toBe(false);
    });

    it("restores a catalog document whose opener delegates to the workspace API", async () => {
      const api = {
        openGraph: vi.fn().mockResolvedValue({
          status: "ok",
          graph: makeLoadedGraph({ revision_id: "r1" }),
        }),
      } as unknown as DashboardApi;
      model = new WorkspaceModel([], [], api);
      model.restorePersistence(
        createWorkspaceEnvelope(
          {
            state: {
              forceParams: {
                repulsion: -100,
                linkDistance: 120,
                collisionRadius: 40,
                centerStrength: 0.1,
                alphaDecay: 0.03,
              },
              simulationParams: {
                initial_foothold_node_id: "",
                monte_carlo_trials: 10,
                iterations_per_run: 20,
                max_attempts: 1,
                generate_seed: false,
                seed: 0,
              },
              optimizationParams: {
                strategy: "cvss" as const,
                budget: 2,
                simulation_params: {
                  initial_foothold_node_id: "",
                  monte_carlo_trials: 10,
                  iterations_per_run: 20,
                  max_attempts: 1,
                  generate_seed: false,
                  seed: 0,
                },
              },
            },
            documents: [
              { kind: "document-catalog", ids: {}, title: "Documents" },
            ],
            selectedDocumentKey: "document-catalog:",
          },
          1,
        ),
      );

      const catalog = model.activeDocument;
      expect(catalog?.kind).toBe("document-catalog");

      const item: DocumentCatalogItem = {
        id: "graph-1",
        kind: "graph",
        graph_id: "graph-1",
        graph_revision_id: "r1",
        graph_title: "Gateway",
        revision_kind: "original",
        revision_number: 1,
        created_at: "2026-01-01T00:00:00Z",
      };
      await expect(
        (catalog as { openItem(item: DocumentCatalogItem): unknown }).openItem(
          item,
        ),
      ).resolves.toBe(true);
      expect(api.openGraph).toHaveBeenCalledWith("r1");
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

    it("opens one Documents catalog tab", () => {
      model.handleCreateDocument("document-catalog");
      const catalog = model.activeDocument;
      model.handleCreateDocument("document-catalog");

      expect(catalog?.kind).toBe("document-catalog");
      expect(catalog?.title).toBe("Documents");
      expect(model.documents).toEqual([catalog]);
    });

    it("opens one Runs tab", () => {
      model.handleCreateDocument("runs");
      const runs = model.activeDocument;
      model.handleCreateDocument("runs");

      expect(runs?.kind).toBe("runs");
      expect(runs?.title).toBe("Runs");
      expect(model.documents).toEqual([runs]);
    });
  });

  describe("openCatalogItem", () => {
    const simulation: DocumentCatalogItem = {
      id: "simulation-1",
      kind: "simulation_report",
      graph_id: "g1",
      graph_revision_id: "r1",
      graph_title: "Topology",
      revision_kind: "original",
      revision_number: 1,
      created_at: "2026-01-01T00:00:00Z",
    };

    const optimization: DocumentCatalogItem = {
      ...simulation,
      id: "optimization-1",
      kind: "optimization_report",
      strategy: "cvss",
    };

    it("loads historical reports once and focuses existing tabs", async () => {
      const api = {
        requestSimulationReport: vi.fn(),
        requestOptimizationReport: vi.fn(),
      } as unknown as DashboardApi;

      await model.openCatalogItem(api, simulation);
      const simulationReport = model.activeDocument;
      await model.openCatalogItem(api, simulation);
      await model.openCatalogItem(api, optimization);
      const optimizationReport = model.activeDocument;
      await model.openCatalogItem(api, optimization);

      expect(model.documents).toEqual([simulationReport, optimizationReport]);
      expect(model.activeDocument).toBe(optimizationReport);
      if (
        !optimizationReport ||
        optimizationReport.kind !== "optimization-report"
      ) {
        throw new Error("Expected optimization report");
      }
      expect(optimizationReport.openOptimizedGraph).toBeUndefined();
      expect(optimizationReport.graphDiff).toBeUndefined();
      expect(api.requestSimulationReport).toHaveBeenCalledTimes(1);
      expect(api.requestSimulationReport).toHaveBeenCalledWith(
        simulationReport!.id,
        "simulation-1",
      );
      expect(api.requestOptimizationReport).toHaveBeenCalledTimes(1);
      expect(api.requestOptimizationReport).toHaveBeenCalledWith(
        optimizationReport.id,
        "optimization-1",
      );
    });

    it("prepares optimized graph actions for historical reports with an output revision", async () => {
      const api = {
        requestOptimizationReport: vi.fn(),
        openGraph: vi.fn((revisionId: string) =>
          Promise.resolve({
            status: "ok" as const,
            graph: makeLoadedGraph({ revision_id: revisionId }),
          }),
        ),
        compareGraphs: vi.fn().mockResolvedValue({
          status: "ok",
          result: {
            graph: makeLoadedGraph(),
            node_status: [],
            edge_status: [],
            node_counts: { added: 0, removed: 0, unchanged: 0 },
            edge_counts: { added: 0, removed: 0, unchanged: 0 },
          },
        }),
      } as unknown as DashboardApi;
      const item: DocumentCatalogItem = {
        ...optimization,
        output_graph_revision_id: "optimized-r1",
      };

      await model.openCatalogItem(api, item);

      const report = model.activeDocument;
      if (!report || report.kind !== "optimization-report") {
        throw new Error("Expected optimization report");
      }
      expect(report.optimizedGraphRevisionId).toBe("optimized-r1");
      expect(report.status).toBe("loading");
      expect(api.requestOptimizationReport).toHaveBeenCalledWith(
        report.id,
        "optimization-1",
      );

      await expect(report.openOptimizedGraph?.()).resolves.toBe(true);
      expect(model.activeGraph?.loadedRevisionId).toBe("optimized-r1");
      await expect(report.loadGraphDiff()).resolves.toBe(true);

      expect(api.openGraph).toHaveBeenCalledWith("optimized-r1");
      expect(api.openGraph).toHaveBeenCalledWith("r1");
      expect(api.compareGraphs).toHaveBeenCalledWith("r1", "optimized-r1");
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

    it("keeps active analysis reports open until they load or fail", () => {
      const report = model.createPendingOptimizationReport({
        graphId: "g1",
        graphRevisionId: "r1",
        graphTitle: "Test",
        correlationId: "corr-optimization",
        strategy: "cvss",
        budget: 1,
      });

      for (const status of ["pending", "ready", "loading"] as const) {
        report.status = status;
        expect(model.canCloseDocument(report)).toBe(false);
      }
      model.closeDocument(report.id);
      expect(model.documents).toContain(report);

      report.status = "error";
      expect(model.canCloseDocument(report)).toBe(true);
      model.closeDocument(report.id);
      expect(model.documents).not.toContain(report);

      const loadedReport = model.createPendingOptimizationReport({
        graphId: "g1",
        graphRevisionId: "r1",
        graphTitle: "Test",
        correlationId: "corr-loaded-optimization",
        strategy: "cvss",
        budget: 1,
      });
      loadedReport.status = "loaded";
      expect(model.canCloseDocument(loadedReport)).toBe(true);
    });
  });

  describe("reorderDocuments", () => {
    it("moves a middle tab right and can move a tab to the final position", () => {
      const first = model.createGraphDocument();
      const second = model.createGraphDocument();
      const third = model.createGraphDocument();

      model.reorderDocuments(second.id, third.id);

      expect(model.documents.map((document) => document.id)).toEqual([
        first.id,
        third.id,
        second.id,
      ]);
      expect(model.selectedDocumentId).toBe(third.id);

      model.reorderDocuments(first.id, second.id);
      expect(model.documents.map((document) => document.id)).toEqual([
        third.id,
        second.id,
        first.id,
      ]);
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

    it("marks background reports unread and selected reports read", () => {
      const report = model.createPendingOptimizationReport({
        graphId: "g1",
        graphRevisionId: "r1",
        graphTitle: "Test",
        correlationId: "corr-optimization",
        strategy: "cvss",
        budget: 1,
      });
      model.createGraphDocument();

      model.markReportReadState(report);
      expect(report.hasUnread).toBe(true);

      model.selectDocument(report.id);
      model.markReportReadState(report);
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

    it("activates an already-open dirty revision before fetching", async () => {
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

      expect(model.documents).toHaveLength(1);
      expect(model.activeGraph?.title).toBe("Unsaved edit");
      expect(model.activeGraph?.isDirty).toBe(true);
      expect(api.openGraph).not.toHaveBeenCalled();
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
