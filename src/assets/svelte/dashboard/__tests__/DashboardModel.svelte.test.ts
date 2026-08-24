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

function api(): DashboardApi & {
  requestSimulationReport: ReturnType<typeof vi.fn>;
  requestOptimizationReport: ReturnType<typeof vi.fn>;
} {
  return {
    openGraph: vi.fn(),
    saveGraph: vi.fn(),
    runSimulation: vi.fn(),
    runOptimization: vi.fn(),
    requestSimulationReport: vi.fn(),
    requestOptimizationReport: vi.fn(),
    fetchExperiments: vi.fn().mockResolvedValue({ experiments: [] }),
    fetchOptimizationRuns: vi.fn().mockResolvedValue({ runs: [] }),
    fetchRuns: vi.fn().mockResolvedValue({ runs: [] }),
    fetchGraphConnectivity: vi.fn(),
    fetchGraphProjection: vi.fn(),
    fetchDocumentCatalog: vi.fn(),
    createNodeDraft: vi.fn(),
    createConnectionDraft: vi.fn(),
    compareGraphs: vi.fn(),
    setGraphRevisionFavorite: vi.fn(),
    createFolder: vi.fn(),
    deleteFolder: vi.fn(),
    moveGraphToFolder: vi.fn(),
    listManifests: vi.fn().mockResolvedValue({ manifests: [] }),
    getManifest: vi.fn(),
    saveManifest: vi.fn(),
    startEvaluation: vi.fn(),
    requestEvaluationReport: vi.fn(),
    requestEvaluationAnalysis: vi.fn(),
  } as DashboardApi & {
    requestSimulationReport: ReturnType<typeof vi.fn>;
    requestOptimizationReport: ReturnType<typeof vi.fn>;
  };
}

function createSimulationReport(model: DashboardModel) {
  return model.workspace.createPendingReport({
    graphId: "g1",
    graphRevisionId: "r1",
    graphTitle: "Topology",
    correlationId: "simulation-1",
  });
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

    expect(dashboardApi.requestSimulationReport).toHaveBeenCalledWith(
      expect.any(String),
      "experiment-1",
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
    const report = createSimulationReport(model);

    model.onSimulationCompleted({
      correlation_id: "simulation-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      experiment_id: "experiment-1",
    });

    expect(dashboardApi.requestSimulationReport).toHaveBeenCalledWith(
      report.id,
      "experiment-1",
    );
    expect(report.status).toBe("loading");
  });

  it("handles an evaluation event that arrives before its start reply", () => {
    model.onEvaluationCompleted({
      run_id: "evaluation-1",
      manifest_id: "manifest-1",
      manifest_title: "Evaluation manifest",
      source_graph_revision_id: "r1",
    });

    model.manifest.onStarted?.("evaluation-1", {
      id: "manifest-1",
      manifest_id: "manifest-1",
      title: "Evaluation manifest",
    });

    const report = model.workspace.documents.find(
      (document) => document.kind === "analysis-report",
    );
    expect(report).toMatchObject({
      runId: "evaluation-1",
      status: "loading",
    });
    expect(dashboardApi.requestEvaluationReport).toHaveBeenCalledWith(
      report?.id,
      "evaluation-1",
    );
  });

  it("fetches the failed evaluation report so the failure reason is shown", () => {
    model.onEvaluationFailed({
      run_id: "evaluation-1",
      manifest_id: "manifest-1",
      manifest_title: "Evaluation manifest",
      error: { code: "internal_error" },
    });

    model.manifest.onStarted?.("evaluation-1", {
      id: "manifest-1",
      manifest_id: "manifest-1",
      title: "Evaluation manifest",
    });

    const report = model.workspace.documents.find(
      (document) => document.kind === "analysis-report",
    );
    expect(report).toMatchObject({
      runId: "evaluation-1",
      status: "loading",
    });
    expect(dashboardApi.requestEvaluationReport).toHaveBeenCalledWith(
      report?.id,
      "evaluation-1",
    );
  });

  it("routes evaluation progress to the pending report by run ID", () => {
    model.manifest.onStarted?.("evaluation-1", {
      id: "manifest-1",
      manifest_id: "manifest-1",
      title: "Evaluation manifest",
    });

    model.onProgress("evaluation", {
      correlation_id: "evaluation-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      completed: 4,
      total: 13,
      detail: "Baseline attack trials: 3 of 5",
    });

    const report = model.workspace.documents.find(
      (document) => document.kind === "analysis-report",
    );
    expect(report).toMatchObject({
      runId: "evaluation-1",
      progress: {
        completed: 4,
        total: 13,
        detail: "Baseline attack trials: 3 of 5",
      },
    });
  });

  it("routes report assembly progress to the loading report by run ID", () => {
    model.onEvaluationCompleted({
      run_id: "evaluation-1",
      manifest_id: "manifest-1",
      manifest_title: "Evaluation manifest",
      source_graph_revision_id: "r1",
    });

    model.manifest.onStarted?.("evaluation-1", {
      id: "manifest-1",
      manifest_id: "manifest-1",
      title: "Evaluation manifest",
    });

    model.onReportProgress("evaluation", {
      correlation_id: "evaluation-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      completed: 2,
      total: 4,
      detail: "Summarizing plans",
    });

    const report = model.workspace.documents.find(
      (document) => document.kind === "analysis-report",
    );
    expect(report).toMatchObject({
      runId: "evaluation-1",
      status: "loading",
      loadProgress: { completed: 2, total: 4, detail: "Summarizing plans" },
    });
  });

  it("routes simulation report assembly progress to the loading report by experiment ID", () => {
    const simulation = createSimulationReport(model);
    model.onSimulationCompleted({
      correlation_id: "simulation-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      experiment_id: "experiment-1",
    });

    model.onReportProgress("simulation", {
      correlation_id: "experiment-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      completed: 4,
      total: 6,
      detail: "Materializing operational flows",
    });

    expect(simulation).toMatchObject({
      status: "loading",
      loadProgress: {
        completed: 4,
        total: 6,
        detail: "Materializing operational flows",
      },
    });
  });

  it("routes optimization report assembly progress to the loading report by optimization ID", async () => {
    model.workspace.selectDocument(model.workspace.documents[0]!.id);
    vi.mocked(dashboardApi.runOptimization).mockImplementation(
      async (graphRevisionId, correlationId) => ({
        status: "accepted",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
      }),
    );
    await model.runActiveOptimization();

    model.onOptimizationCompleted({
      correlation_id: model.workspace.documents.find(
        (document) => document.kind === "optimization-report",
      )!.correlationId!,
      graph_id: "g1",
      graph_revision_id: "r1",
      output_graph_revision_id: "optimized-r1",
      optimization_id: "optimization-1",
    });

    model.onReportProgress("optimization", {
      correlation_id: "optimization-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      completed: 2,
      total: 2,
      detail: "Building action summaries",
    });

    const report = model.workspace.documents.find(
      (document) => document.kind === "optimization-report",
    );
    expect(report).toMatchObject({
      status: "loading",
      loadProgress: {
        completed: 2,
        total: 2,
        detail: "Building action summaries",
      },
    });
  });

  it("buffers the latest evaluation progress until the report is created", () => {
    model.onProgress("evaluation", {
      correlation_id: "evaluation-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      completed: 1,
      total: 13,
      detail: "Selecting plans",
    });
    model.onProgress("evaluation", {
      correlation_id: "evaluation-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      completed: 4,
      total: 13,
      detail: "Baseline attack trials: 3 of 5",
    });

    model.manifest.onStarted?.("evaluation-1", {
      id: "manifest-1",
      manifest_id: "manifest-1",
      title: "Evaluation manifest",
    });

    const report = model.workspace.documents.find(
      (document) => document.kind === "analysis-report",
    );
    expect(report).toMatchObject({
      runId: "evaluation-1",
      progress: {
        completed: 4,
        total: 13,
        detail: "Baseline attack trials: 3 of 5",
      },
    });
  });

  it("routes progress events to the matching report by kind", async () => {
    const simulation = createSimulationReport(model);

    model.onProgress("simulation", {
      correlation_id: "simulation-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      completed: 3,
      total: 10,
    });

    expect(simulation.progress).toEqual({ completed: 3, total: 10 });

    model.workspace.selectDocument(model.workspace.documents[0]!.id);
    vi.mocked(dashboardApi.runOptimization).mockImplementation(
      async (graphRevisionId, correlationId) => ({
        status: "accepted",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
      }),
    );
    await model.runActiveOptimization();
    const optimization = model.workspace.documents.find(
      (document) => document.kind === "optimization-report",
    );
    if (!optimization || optimization.kind !== "optimization-report")
      throw new Error("Missing report");

    model.onProgress("optimization", {
      correlation_id: optimization.correlationId!,
      graph_id: "g1",
      graph_revision_id: "r1",
      completed: 2,
      total: 5,
      detail: "Scoring defenses",
    });

    expect(optimization.progress).toEqual({
      completed: 2,
      total: 5,
      detail: "Scoring defenses",
    });
  });

  it("ignores report errors with a mismatched report kind", () => {
    const report = createSimulationReport(model);
    model.workspace.selectDocument(model.workspace.documents[0]!.id);
    model.onReportErrorEvent({
      reportKind: "optimization",
      payload: {
        document_id: report.id,
        optimization_id: "optimization-1",
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
        error: { code: "internal_error" },
      },
    });

    expect(report.status).toBe("error");
    expect(report.errorReason).toBe("The operation could not be completed.");
    expect(report.hasUnread).toBe(true);
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
    expect(dashboardApi.requestOptimizationReport).toHaveBeenCalledWith(
      report.id,
      "optimization-1",
    );
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

  it("does not re-request an evaluation report that is already loaded", () => {
    model.manifest.onStarted?.("evaluation-1", {
      id: "manifest-1",
      manifest_id: "manifest-1",
      title: "Evaluation manifest",
    });
    const report = model.workspace.documents.find(
      (document) => document.kind === "analysis-report",
    )!;

    model.onReportReadyEvent({
      reportKind: "evaluation",
      payload: {
        document_id: report.id,
        report: {
          run_id: "evaluation-1",
          status: "completed",
          failure_reason: null,
          manifest_id: "manifest-1",
          manifest_title: "Evaluation manifest",
          graph_id: "g1",
          source_graph_revision_id: "r1",
          source_graph_title: "Topology",
          plans: [],
          experiments: [],
        },
      },
    });
    expect(report.status).toBe("loaded");

    const before = vi.mocked(dashboardApi.requestEvaluationReport).mock.calls
      .length;
    model.onEvaluationCompleted({
      run_id: "evaluation-1",
      manifest_id: "manifest-1",
      manifest_title: "Evaluation manifest",
      source_graph_revision_id: "r1",
    });

    expect(
      vi.mocked(dashboardApi.requestEvaluationReport).mock.calls.length,
    ).toBe(before);
    expect(report.status).toBe("loaded");
  });

  it("surfaces a not_found evaluation report error without treating it as an internal crash", () => {
    model.manifest.onStarted?.("evaluation-1", {
      id: "manifest-1",
      manifest_id: "manifest-1",
      title: "Evaluation manifest",
    });
    const report = model.workspace.documents.find(
      (document) => document.kind === "analysis-report",
    )!;

    model.onReportErrorEvent({
      reportKind: "evaluation",
      payload: {
        document_id: report.id,
        run_id: "evaluation-1",
        error: { code: "not_found" },
      },
    });

    expect(report.status).toBe("error");
    expect(report.errorReason).toBe("The requested item was not found.");
  });
});
