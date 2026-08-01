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
    fetchExperiments: vi.fn(),
    fetchGraphConnectivity: vi.fn(),
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
    vi.mocked(dashboardApi.runSimulation).mockResolvedValue({
      status: "accepted",
      graph_revision_id: "r2",
      correlation_id: "simulation-1",
    });

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
      correlation_id: report.correlationId,
      graph_id: "g1",
      graph_revision_id: "optimized-r1",
      report: {
        strategy: "cvss",
        requested_budget: 1,
        used_budget: 1,
        runtime_ms: 1,
        actions: [],
      },
    });

    expect(report.graphRevisionId).toBe("r1");
    expect(report.optimizedGraphRevisionId).toBe("optimized-r1");
  });
});
