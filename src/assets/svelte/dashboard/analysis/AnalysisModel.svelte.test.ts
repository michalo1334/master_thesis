import { describe, expect, it, vi } from "vitest";
import { AnalysisModel } from "./AnalysisModel.svelte";
import type { DashboardApi } from "../dashboard-api";
import type { LoadedGraph } from "../contract";
import { WorkspaceModel } from "../workspace/WorkspaceModel.svelte";

function graph(): LoadedGraph {
  return {
    id: "graph-1",
    title: "Target graph",
    revision_id: "revision-1",
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
  };
}

function api(): DashboardApi {
  return {
    openGraph: vi.fn().mockResolvedValue({ status: "ok", graph: graph() }),
    saveGraph: vi.fn(),
    runSimulation: vi.fn().mockResolvedValue({
      status: "accepted",
      graph_revision_id: "revision-1",
      correlation_id: "simulation-1",
    }),
    runOptimization: vi
      .fn()
      .mockImplementation(async (graphRevisionId, correlationId) => ({
        status: "accepted",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
      })),
    requestSimulationReport: vi.fn(),
    requestOptimizationReport: vi.fn(),
    fetchExperiments: vi.fn(),
    fetchOptimizationRuns: vi.fn(),
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

describe("AnalysisModel", () => {
  it("returns to analysis after closing the target picker", () => {
    const model = new AnalysisModel(api(), new WorkspaceModel());

    model.openDialog();
    model.openTargetPicker();

    expect(model.open).toBe(false);
    expect(model.targetPickerOpen).toBe(true);

    model.setTargetPickerOpen(false);

    expect(model.open).toBe(true);
    expect(model.targetPickerOpen).toBe(false);
  });

  it("starts every selected operation against one saved target", async () => {
    const dashboardApi = api();
    const workspace = new WorkspaceModel([
      {
        graph_id: "graph-1",
        revision_id: "revision-1",
        title: "Target graph",
        parent_revision_id: null,
        revision_kind: "original",
        revision_number: 1,
        node_count: 1,
        edge_count: 0,
        is_favorite: false,
      },
    ]);
    const model = new AnalysisModel(dashboardApi, workspace);

    await model.selectTarget("revision-1");
    model.includeSimulation = true;
    model.includeOptimization = true;
    model.setStrategies(["cvss", "simulation_informed"]);

    await expect(model.run()).resolves.toBe(true);

    expect(dashboardApi.openGraph).toHaveBeenCalledWith("revision-1");
    expect(dashboardApi.runSimulation).toHaveBeenCalledWith(
      "revision-1",
      expect.any(String),
      expect.anything(),
    );
    expect(dashboardApi.runOptimization).toHaveBeenCalledTimes(2);
    expect(dashboardApi.runOptimization).toHaveBeenNthCalledWith(
      1,
      "revision-1",
      expect.any(String),
      expect.objectContaining({ strategy: "cvss" }),
    );
    expect(dashboardApi.runOptimization).toHaveBeenNthCalledWith(
      2,
      "revision-1",
      expect.any(String),
      expect.objectContaining({ strategy: "simulation_informed" }),
    );
    expect(workspace.documents).toHaveLength(3);
    expect(workspace.documents.map((document) => document.kind)).toEqual([
      "optimization-report",
      "optimization-report",
      "simulation-report",
    ]);
  });

  it("requires simulation settings for every strategy that needs them", async () => {
    const model = new AnalysisModel(api(), new WorkspaceModel());

    await model.selectTarget("revision-1");
    model.includeOptimization = true;

    model.setStrategies(["topology_segmentation"]);
    expect(model.runnableStrategies).toEqual(["topology_segmentation"]);
    expect(model.needsSimulationSettings).toBe(true);
    expect(model.needsFoothold).toBe(true);

    model.setStrategies(["simulation_informed"]);
    expect(model.needsSimulationSettings).toBe(true);

    model.setStrategies(["simulated_annealing"]);
    expect(model.needsSimulationSettings).toBe(true);

    model.setStrategies(["cvss"]);
    expect(model.needsSimulationSettings).toBe(false);
  });

  it("surfaces the rejection reason of a standalone simulation", async () => {
    const dashboardApi = api();
    vi.mocked(dashboardApi.runSimulation).mockResolvedValue({
      status: "rejected",
      graph_revision_id: "revision-1",
      correlation_id: "simulation-1",
      reason: "invalid_request",
    });
    const workspace = new WorkspaceModel();
    const model = new AnalysisModel(dashboardApi, workspace);

    await model.selectTarget("revision-1");
    model.includeSimulation = true;

    await expect(model.run()).resolves.toBe(false);
    expect(workspace.statusMessage).toBe(
      "Simulation rejected: invalid_request",
    );
  });

  it("marks a failed background optimization report unread", async () => {
    const dashboardApi = api();
    vi.mocked(dashboardApi.runOptimization)
      .mockResolvedValueOnce({
        status: "rejected",
        graph_revision_id: "revision-1",
        correlation_id: "optimization-1",
        reason: "Rejected",
      })
      .mockResolvedValueOnce({
        status: "accepted",
        graph_revision_id: "revision-1",
        correlation_id: "optimization-2",
      });
    const workspace = new WorkspaceModel();
    const model = new AnalysisModel(dashboardApi, workspace);

    await model.selectTarget("revision-1");
    model.includeOptimization = true;
    model.setStrategies(["cvss", "simulation_informed"]);

    await expect(model.run()).resolves.toBe(true);

    const failed = workspace.documents[0];
    if (!failed || failed.kind !== "optimization-report") {
      throw new Error("Missing failed optimization report");
    }
    expect(failed.status).toBe("error");
    expect(failed.hasUnread).toBe(true);
  });
});
