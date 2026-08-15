import { beforeEach, describe, expect, it, vi } from "vitest";
import { DashboardModel } from "../DashboardModel.svelte";
import type { DashboardApi } from "../dashboard-api";
import type { LoadedGraph } from "../contract";

function graph(overrides: Partial<LoadedGraph> = {}): LoadedGraph {
  return {
    id: "g1",
    title: "Topology",
    revision_id: "r1",
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    nodes: [
      {
        id: "host-1",
        type: "Host",
        data: { name: "Gateway" },
        view_data: { x_pos: 0, y_pos: 0 },
      },
    ],
    edges: [],
    ...overrides,
  };
}

function api(): DashboardApi & { requestReport: ReturnType<typeof vi.fn> } {
  return {
    openGraph: vi.fn(),
    saveGraph: vi.fn(),
    runSimulation: vi.fn(),
    runOptimization: vi.fn(),
    runWorkflow: vi.fn(),
    requestReport: vi.fn(),
    fetchExperiments: vi.fn().mockResolvedValue({ experiments: [] }),
    fetchOptimizationRuns: vi.fn().mockResolvedValue({ runs: [] }),
    fetchGraphConnectivity: vi.fn(),
    fetchGraphProjection: vi.fn(),
    createNodeDraft: vi.fn(),
    createConnectionDraft: vi.fn(),
    compareGraphs: vi.fn(),
    setGraphRevisionFavorite: vi.fn(),
    createFolder: vi.fn(),
    deleteFolder: vi.fn(),
    moveGraphToFolder: vi.fn(),
  } as DashboardApi & { requestReport: ReturnType<typeof vi.fn> };
}

describe("DashboardModel", () => {
  let model: DashboardModel;
  let dashboardApi: ReturnType<typeof api>;

  beforeEach(async () => {
    dashboardApi = api();
    model = new DashboardModel(dashboardApi);
    await model.workspace.openLoadedGraph(graph(), dashboardApi);
  });

  it("saves before simulating and scopes the report to the saved revision", async () => {
    model.workspace.activeGraph!.addNode({
      id: "host-2",
      type: "Host",
      data: { name: "API" },
      view_data: { x_pos: 1, y_pos: 1 },
    });
    vi.mocked(dashboardApi.saveGraph).mockResolvedValue({
      status: "ok",
      graph: graph({ revision_id: "r2" }),
    });
    vi.mocked(dashboardApi.runSimulation).mockImplementation(
      async (graphRevisionId, correlationId) => ({
        status: "accepted",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
      }),
    );

    await model.runActiveSimulation();

    expect(dashboardApi.runSimulation).toHaveBeenCalledWith(
      "r2",
      expect.any(String),
      expect.anything(),
    );
    const report = model.workspace.documents.find(
      (document) => document.kind === "simulation-report",
    );
    expect(report).toMatchObject({ graphId: "g1", graphRevisionId: "r2" });
  });

  it("surfaces the rejection error of a standalone simulation", async () => {
    vi.mocked(dashboardApi.runSimulation).mockResolvedValue({
      status: "rejected",
      graph_revision_id: "r1",
      correlation_id: "simulation-1",
      error: { code: "invalid_graph" },
    });

    await model.runActiveSimulation();

    expect(model.workspace.statusMessage).toBe(
      "Simulation rejected: The graph is invalid.",
    );
  });

  it("creates the pending simulation report before synchronous terminal events", async () => {
    vi.mocked(dashboardApi.runSimulation).mockImplementation(
      async (graphRevisionId, correlationId) => {
        const report = model.workspace.documents.find(
          (document) =>
            document.kind === "simulation-report" &&
            document.correlationId === correlationId,
        );
        expect(report).toBeDefined();

        model.onSimulationCompleted({
          correlation_id: correlationId,
          graph_id: "g1",
          graph_revision_id: graphRevisionId,
          experiment_id: "experiment-1",
        });
        return {
          status: "accepted",
          graph_revision_id: graphRevisionId,
          correlation_id: correlationId,
        };
      },
    );

    await model.runActiveSimulation();

    expect(dashboardApi.requestReport).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "simulation",
        reportId: "experiment-1",
        graphRevisionId: "r1",
      }),
    );
  });

  it("routes a synchronous simulation failure to the pending report", async () => {
    vi.mocked(dashboardApi.runSimulation).mockImplementation(
      async (graphRevisionId, correlationId) => {
        model.onSimulationFailed({
          correlation_id: correlationId,
          graph_id: "g1",
          graph_revision_id: graphRevisionId,
          error: { code: "internal_error" },
        });
        return {
          status: "accepted",
          graph_revision_id: graphRevisionId,
          correlation_id: correlationId,
        };
      },
    );

    await model.runActiveSimulation();

    const report = model.workspace.documents.find(
      (document) => document.kind === "simulation-report",
    );
    expect(report).toMatchObject({
      status: "error",
      errorReason: "The operation could not be completed.",
    });
  });

  it("routes simulation events by persisted revision ID", () => {
    const report = model.workspace.createPendingReport({
      graphId: "g1",
      graphRevisionId: "r1",
      graphTitle: "Topology",
      correlationId: "simulation-1",
    });

    model.onSimulationCompleted({
      correlation_id: "simulation-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      experiment_id: "experiment-1",
    });

    expect(dashboardApi.requestReport).toHaveBeenCalledWith({
      type: "simulation",
      documentId: report.id,
      reportId: "experiment-1",
      graphRevisionId: "r1",
    });
    expect(report.status).toBe("loading");
  });

  it("ignores report errors with a mismatched report kind", () => {
    const report = model.workspace.createPendingReport({
      graphId: "g1",
      graphRevisionId: "r1",
      graphTitle: "Topology",
      correlationId: "simulation-1",
    });
    model.workspace.selectDocument(model.workspace.documents[0]!.id);
    model.onReportErrorEvent({
      reportKind: "optimization",
      payload: {
        document_id: report.id,
        optimization_id: "optimization-1",
        graph_revision_id: "r1",
        error: { code: "internal_error" },
      },
    });

    expect(report.status).toBe("pending");
    expect(report.hasUnread).toBe(false);

    model.onReportErrorEvent({
      reportKind: "simulation",
      payload: {
        document_id: report.id,
        experiment_id: "experiment-1",
        graph_revision_id: "r1",
        error: { code: "internal_error" },
      },
    });

    expect(report.status).toBe("error");
    expect(report.errorReason).toBe("The operation could not be completed.");
    expect(report.hasUnread).toBe(true);
  });

  it("forwards workflow events to analysis", () => {
    const onWorkflowCompleted = vi.spyOn(model.analysis, "onWorkflowCompleted");
    const onWorkflowFailed = vi.spyOn(model.analysis, "onWorkflowFailed");
    const completed = {
      workflow_id: "workflow-1",
      baseline_experiment_id: "baseline-1",
      optimization_id: "optimization-1",
      output_graph_revision_id: "r2",
      after_experiment_id: "after-1",
    };
    const failed = {
      workflow_id: "workflow-1",
      error: { code: "internal_error" as const },
    };

    model.onWorkflowCompleted(completed);
    model.onWorkflowFailed(failed);

    expect(onWorkflowCompleted).toHaveBeenCalledWith(completed);
    expect(onWorkflowFailed).toHaveBeenCalledWith(failed);
  });

  it("uses the source and optimized revisions for optimization reports", async () => {
    vi.mocked(dashboardApi.runOptimization).mockImplementation(
      async (graphRevisionId, correlationId) => ({
        status: "accepted",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
      }),
    );

    await model.runActiveOptimization();
    const report = model.workspace.documents.find(
      (document) => document.kind === "optimization-report",
    );
    if (!report || report.kind !== "optimization-report")
      throw new Error("Missing report");

    model.onOptimizationCompleted({
      correlation_id: report.correlationId!,
      graph_id: "g1",
      graph_revision_id: "r1",
      output_graph_revision_id: "optimized-r1",
      optimization_id: "optimization-1",
    });

    expect(report.graphRevisionId).toBe("r1");
    expect(report.optimizedGraphRevisionId).toBe("optimized-r1");
    expect(dashboardApi.requestReport).toHaveBeenCalledWith({
      type: "optimization",
      documentId: report.id,
      reportId: "optimization-1",
      graphRevisionId: "r1",
    });
    const openOptimizedGraph = vi
      .spyOn(model.workspace, "openOptimizationResult")
      .mockResolvedValue(true);
    const loadGraphDiff = vi
      .spyOn(model.workspace, "loadOptimizationGraphDiff")
      .mockResolvedValue(undefined);

    await report.openOptimizedGraph!();
    await report.loadGraphDiff();

    expect(openOptimizedGraph).toHaveBeenCalledWith(
      dashboardApi,
      "optimized-r1",
    );
    expect(loadGraphDiff).toHaveBeenCalledWith(
      dashboardApi,
      "r1",
      "optimized-r1",
    );

    model.onReportReadyEvent({
      reportKind: "optimization",
      payload: {
        document_id: report.id,
        report: {
          optimization_id: "optimization-1",
          graph_id: "g1",
          graph_title: "Topology",
          graph_revision_id: "r1",
          report: {
            strategy: "cvss",
            objective: "blast_radius",
            requested_budget: 1,
            used_budget: 1,
            runtime_ms: 1,
            actions: [],
          },
        },
      },
    });
    expect(report.status).toBe("loaded");
  });
});
