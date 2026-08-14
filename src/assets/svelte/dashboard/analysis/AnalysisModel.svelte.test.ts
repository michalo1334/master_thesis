import { describe, expect, it, vi } from "vitest";
import { waitFor } from "@testing-library/svelte";
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
    runSimulation: vi
      .fn()
      .mockImplementation(async (graphRevisionId, correlationId) => ({
        status: "accepted",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
      })),
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

  it("starts every selected standalone optimization against one saved target", async () => {
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
    model.includeOptimization = true;
    model.setStrategies(["cvss", "simulation_informed"]);

    await expect(model.run()).resolves.toBe(true);

    expect(dashboardApi.openGraph).toHaveBeenCalledWith("revision-1");
    expect(dashboardApi.runSimulation).not.toHaveBeenCalled();
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
    expect(workspace.documents).toHaveLength(2);
    expect(workspace.documents.map((document) => document.kind)).toEqual([
      "optimization-report",
      "optimization-report",
    ]);
  });

  it("uses blast radius for strategies that do not support mission impact", async () => {
    const dashboardApi = api();
    const workspace = new WorkspaceModel();
    const model = new AnalysisModel(dashboardApi, workspace);

    await model.selectTarget("revision-1");
    workspace.onOptimizationParamsChange({ objective: "mission_impact" });
    model.includeOptimization = true;
    model.setStrategies([
      "cvss",
      "topology_segmentation",
      "simulation_informed",
      "simulated_annealing",
    ]);

    await expect(model.run()).resolves.toBe(true);

    const params = vi
      .mocked(dashboardApi.runOptimization)
      .mock.calls.map((call) => call[2]);
    expect(params).toEqual([
      expect.objectContaining({
        strategy: "cvss",
        objective: "blast_radius",
      }),
      expect.objectContaining({
        strategy: "topology_segmentation",
        objective: "blast_radius",
      }),
      expect.objectContaining({
        strategy: "simulation_informed",
        objective: "mission_impact",
      }),
      expect.objectContaining({
        strategy: "simulated_annealing",
        objective: "mission_impact",
      }),
    ]);
  });

  it("runs a compound sequence through pending reports with parameter snapshots", async () => {
    const dashboardApi = api();
    vi.mocked(dashboardApi.runSimulation).mockImplementation(
      async (graphRevisionId, correlationId) => ({
        status: "accepted",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
      }),
    );
    vi.mocked(dashboardApi.runOptimization).mockImplementation(
      async (graphRevisionId, correlationId) => ({
        status: "accepted",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
      }),
    );
    vi.mocked(dashboardApi.openGraph).mockImplementation(
      async (revisionId) => ({
        status: "ok",
        graph: { ...graph(), revision_id: revisionId },
      }),
    );
    const workspace = new WorkspaceModel();
    const model = new AnalysisModel(dashboardApi, workspace);

    await model.selectTarget("revision-1");
    workspace.onSimulationParamsChange({ seed: 7 });
    model.includeSimulation = true;
    model.includeOptimization = true;
    model.setStrategies(["cvss"]);

    await expect(model.run()).resolves.toBe(true);
    expect(dashboardApi.runSimulation).toHaveBeenCalledTimes(1);
    expect(dashboardApi.runOptimization).not.toHaveBeenCalled();
    expect(model.canRun).toBe(false);

    workspace.onSimulationParamsChange({ seed: 99 });
    const baseline = workspace.documents.find(
      (document) => document.kind === "simulation-report",
    );
    if (!baseline || baseline.kind !== "simulation-report") {
      throw new Error("Missing baseline simulation report");
    }
    model.onSimulationCompleted({
      correlation_id: baseline.correlationId!,
      graph_id: "graph-1",
      graph_revision_id: "revision-1",
      experiment_id: "baseline-experiment",
    });

    await waitFor(() =>
      expect(model.sequence.stage).toBe("awaiting-optimization"),
    );
    const optimization = workspace.documents.find(
      (document) => document.kind === "optimization-report",
    );
    if (!optimization || optimization.kind !== "optimization-report") {
      throw new Error("Missing optimization report");
    }
    model.onOptimizationCompleted({
      correlation_id: optimization.correlationId!,
      graph_id: "graph-1",
      graph_revision_id: "revision-1",
      optimization_id: "optimization-1",
      output_graph_revision_id: "optimized-r1",
    });

    await waitFor(() => expect(model.sequence.stage).toBe("awaiting-after"));
    expect(dashboardApi.openGraph).toHaveBeenLastCalledWith("optimized-r1");
    expect(dashboardApi.runSimulation).toHaveBeenLastCalledWith(
      "optimized-r1",
      expect.any(String),
      expect.objectContaining({ seed: 7 }),
    );

    const after = workspace.documents.filter(
      (document) => document.kind === "simulation-report",
    )[1];
    if (!after || after.kind !== "simulation-report") {
      throw new Error("Missing after simulation report");
    }
    model.onSimulationCompleted({
      correlation_id: after.correlationId!,
      graph_id: "graph-1",
      graph_revision_id: "optimized-r1",
      experiment_id: "after-experiment",
    });

    expect(model.sequence.stage).toBe("completed");
    const comparison = workspace.documents.find(
      (document) => document.kind === "comparison-report",
    );
    expect(comparison).toMatchObject({
      baselineReport: baseline,
      optimizationReport: optimization,
      postOptimizationReport: after,
    });
    expect(workspace.selectedDocumentId).toBe(comparison?.id);
  });

  it("keeps the saved source revision when the active graph changes during the baseline", async () => {
    const dashboardApi = api();
    vi.mocked(dashboardApi.openGraph).mockResolvedValue({
      status: "ok",
      graph: graph(),
    });
    vi.mocked(dashboardApi.runSimulation).mockImplementation(
      async (graphRevisionId, correlationId) => ({
        status: "accepted",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
      }),
    );
    vi.mocked(dashboardApi.runOptimization).mockImplementation(
      async (graphRevisionId, correlationId) => ({
        status: "accepted",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
      }),
    );
    vi.mocked(dashboardApi.saveGraph).mockResolvedValue({
      status: "ok",
      graph: {
        ...graph(),
        revision_id: "revision-2",
        revision_number: 2,
      },
    });
    const workspace = new WorkspaceModel();
    await workspace.openLoadedGraph(graph(), dashboardApi);
    const activeGraph = workspace.activeGraph!;
    const model = new AnalysisModel(dashboardApi, workspace);

    await model.selectTarget("revision-1");
    model.includeSimulation = true;
    model.includeOptimization = true;
    model.setStrategies(["cvss"]);

    await expect(model.run()).resolves.toBe(true);
    activeGraph.addNode({
      id: "host-2",
      type: "Host",
      data: { name: "Changed during baseline" },
      view_data: { x_pos: 1, y_pos: 1 },
    });
    await expect(activeGraph.save(dashboardApi)).resolves.toBe(true);
    expect(activeGraph.loadedRevisionId).toBe("revision-2");

    model.onSimulationCompleted({
      correlation_id: model.sequence.baselineSimulationCorrelationId!,
      graph_id: "graph-1",
      graph_revision_id: "revision-1",
      experiment_id: "baseline-experiment",
    });

    await waitFor(() =>
      expect(dashboardApi.runOptimization).toHaveBeenCalledWith(
        "revision-1",
        expect.any(String),
        expect.anything(),
      ),
    );
  });

  it("requires one runnable strategy for a compound sequence", async () => {
    const model = new AnalysisModel(api(), new WorkspaceModel());

    await model.selectTarget("revision-1");
    model.includeSimulation = true;
    model.includeOptimization = true;
    model.setStrategies(["cvss", "simulation_informed"]);

    expect(model.canRun).toBe(false);
    expect(model.compoundValidationMessage).toBe(
      "Select exactly one runnable optimization strategy for the compound sequence.",
    );

    model.setStrategies(["cvss"]);
    expect(model.canRun).toBe(true);
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

  it("surfaces the rejection error of a standalone simulation", async () => {
    const dashboardApi = api();
    vi.mocked(dashboardApi.runSimulation).mockResolvedValue({
      status: "rejected",
      graph_revision_id: "revision-1",
      correlation_id: "simulation-1",
      error: { code: "invalid_graph" },
    });
    const workspace = new WorkspaceModel();
    const model = new AnalysisModel(dashboardApi, workspace);

    await model.selectTarget("revision-1");
    model.includeSimulation = true;

    await expect(model.run()).resolves.toBe(false);
    expect(workspace.statusMessage).toBe(
      "Simulation rejected: The graph is invalid.",
    );
  });

  it("marks a failed background optimization report unread", async () => {
    const dashboardApi = api();
    vi.mocked(dashboardApi.runOptimization)
      .mockImplementationOnce(async (graphRevisionId, correlationId) => ({
        status: "rejected",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
        error: { code: "unknown_strategy" },
      }))
      .mockImplementationOnce(async (graphRevisionId, correlationId) => ({
        status: "accepted",
        graph_revision_id: graphRevisionId,
        correlation_id: correlationId,
      }));
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
