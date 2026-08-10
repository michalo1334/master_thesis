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

function api(): DashboardApi {
  return {
    openGraph: vi.fn(),
    saveGraph: vi.fn(),
    runSimulation: vi.fn(),
    runOptimization: vi.fn(),
    requestSimulationReport: vi.fn(),
    requestOptimizationReport: vi.fn(),
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
  };
}

describe("DashboardModel", () => {
  let model: DashboardModel;
  let dashboardApi: DashboardApi;

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

  it("surfaces the rejection reason of a standalone simulation", async () => {
    vi.mocked(dashboardApi.runSimulation).mockResolvedValue({
      status: "rejected",
      graph_revision_id: "r1",
      correlation_id: "simulation-1",
      reason: "invalid_request",
    });

    await model.runActiveSimulation();

    expect(model.workspace.statusMessage).toBe(
      "Simulation rejected: invalid_request",
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
      "experiment-1",
      "r1",
    );
  });

  it("routes a synchronous simulation failure to the pending report", async () => {
    vi.mocked(dashboardApi.runSimulation).mockImplementation(
      async (graphRevisionId, correlationId) => {
        model.onSimulationFailed({
          correlation_id: correlationId,
          graph_id: "g1",
          graph_revision_id: graphRevisionId,
          reason: "worker_failed",
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
      errorReason: "worker_failed",
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

    expect(dashboardApi.requestSimulationReport).toHaveBeenCalledWith(
      "experiment-1",
      "r1",
    );
    expect(report.status).toBe("loading");
  });

  it("forwards lifecycle events to compound analysis without a matching report", () => {
    const onSimulationCompleted = vi.spyOn(
      model.analysis,
      "onSimulationCompleted",
    );
    const onSimulationFailed = vi.spyOn(model.analysis, "onSimulationFailed");
    const onOptimizationCompleted = vi.spyOn(
      model.analysis,
      "onOptimizationCompleted",
    );
    const onOptimizationFailed = vi.spyOn(
      model.analysis,
      "onOptimizationFailed",
    );
    const simulationCompleted = {
      correlation_id: "simulation-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      experiment_id: "experiment-1",
    };
    const simulationFailed = {
      correlation_id: "simulation-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      reason: "failed",
    };
    const optimizationCompleted = {
      correlation_id: "optimization-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      optimization_id: "optimization-1",
      output_graph_revision_id: "r2",
    };
    const optimizationFailed = {
      correlation_id: "optimization-1",
      graph_id: "g1",
      graph_revision_id: "r1",
      reason: "failed",
    };

    model.onSimulationCompleted(simulationCompleted);
    model.onSimulationFailed(simulationFailed);
    model.onOptimizationCompleted(optimizationCompleted);
    model.onOptimizationFailed(optimizationFailed);

    expect(onSimulationCompleted).toHaveBeenCalledWith(simulationCompleted);
    expect(onSimulationFailed).toHaveBeenCalledWith(simulationFailed);
    expect(onOptimizationCompleted).toHaveBeenCalledWith(optimizationCompleted);
    expect(onOptimizationFailed).toHaveBeenCalledWith(optimizationFailed);
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
      "optimization-1",
      "r1",
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

    model.onOptimizationReportReady({
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
    });
    expect(report.status).toBe("loaded");
  });
});
