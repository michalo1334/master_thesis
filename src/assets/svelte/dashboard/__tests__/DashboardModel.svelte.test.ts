import { describe, it, expect, beforeEach, vi } from "vitest";
import { DashboardModel } from "../DashboardModel.svelte";
import type { DashboardApi } from "../dashboard-api";
import type { LoadedGraph, FetchSimulationReportReply } from "../contract";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";

function makeMockApi(overrides: Partial<DashboardApi> = {}): DashboardApi {
  return {
    openGraph: vi.fn(),
    saveGraph: vi.fn(),
    runSimulation: vi.fn(),
    runOptimization: vi.fn(),
    requestSimulationReport: vi.fn(),
    fetchExperiments: vi.fn(),
    ...overrides,
  };
}

function makeLoadedGraph(overrides: Partial<LoadedGraph> = {}): LoadedGraph {
  return {
    id: "g1",
    title: "Test Graph",
    lock_version: 1,
    nodes: [],
    edges: [],
    ...overrides,
  };
}

function hostNode(id: string) {
  return {
    id,
    type: "Host" as const,
    data: { name: id },
    view_data: { x_pos: 0, y_pos: 0 },
  };
}

function makeReportReply(
  overrides: Partial<FetchSimulationReportReply> = {},
): FetchSimulationReportReply {
  return {
    charts: {
      action_success: [],
      cdf: [],
      convergence: [],
      edge_traversal: [],
      histogram: [],
      host_compromise: [],
    },
    graph: makeLoadedGraph(),
    graph_id: "g1",
    graph_title: "Test Graph",
    graph_version_at_sim: 1,
    iteration_count: 100,
    summary: {
      expected_blast_radius: 2,
      median_blast_radius: 2,
      blast_radius_p95: 4,
      blast_radius_p99: 5,
      min_blast_radius: 1,
      max_blast_radius: 5,
      blast_radius_variance: 1.2,
      host_count: 8,
    },
    experiment_id: "sim-1",
    run_count: 10,
    total_runtime_ms: 500,
    ...overrides,
  };
}

function findReport(
  model: DashboardModel,
  correlationId: string,
): SimulationReportDocument | undefined {
  return model.workspace.documents.find(
    (d) => d.kind === "simulation-report" && d.correlationId === correlationId,
  ) as SimulationReportDocument | undefined;
}

describe("DashboardModel", () => {
  let model: DashboardModel;
  let api: DashboardApi;

  beforeEach(() => {
    api = makeMockApi();
    model = new DashboardModel(api);
  });

  describe("runActiveSimulation", () => {
    it("creates a pending report keyed by correlation ID when simulation is accepted", async () => {
      const graph = makeLoadedGraph({
        id: "g1",
        title: "Topology",
        nodes: [hostNode("host-1")],
      });
      await model.workspace.openLoadedGraph(graph, api);

      vi.mocked(api.runSimulation).mockResolvedValue({
        status: "accepted",
        graph_id: "g1",
        correlation_id: "corr-123",
      });

      await model.runActiveSimulation();

      const report = findReport(model, "corr-123");
      expect(report).toBeDefined();
      expect(report!.kind).toBe("simulation-report");
      expect(report!.correlationId).toBe("corr-123");
      expect(report!.graphId).toBe("g1");
      expect(report!.status).toBe("pending");
      expect(api.runSimulation).toHaveBeenCalledWith(
        "g1",
        expect.any(String),
        expect.objectContaining({ initial_foothold_node_id: "host-1" }),
      );
    });

    it("no-ops when no active graph exists", async () => {
      vi.mocked(api.runSimulation).mockResolvedValue({
        status: "accepted",
        graph_id: "g1",
        correlation_id: "corr-123",
      });

      await model.runActiveSimulation();

      expect(api.runSimulation).not.toHaveBeenCalled();
    });

    it("does not create a report when simulation is rejected", async () => {
      const graph = makeLoadedGraph({ id: "g1" });
      await model.workspace.openLoadedGraph(graph, api);

      vi.mocked(api.runSimulation).mockResolvedValue({
        status: "rejected",
        graph_id: "g1",
        correlation_id: "corr-rejected",
        reason: "Server busy",
      });

      await model.runActiveSimulation();

      const report = findReport(model, "corr-rejected");
      expect(report).toBeUndefined();
    });

    it("keeps same-graph accepted simulations and delivers each completion independently", async () => {
      const graph = makeLoadedGraph({ id: "g1", title: "Topology" });
      await model.workspace.openLoadedGraph(graph, api);
      vi.mocked(api.runSimulation)
        .mockResolvedValueOnce({
          status: "accepted",
          graph_id: "g1",
          correlation_id: "corr-first",
        })
        .mockResolvedValueOnce({
          status: "accepted",
          graph_id: "g1",
          correlation_id: "corr-second",
        });
      await model.runActiveSimulation();
      model.workspace.selectDocument(model.workspace.documents[0].id);
      await model.runActiveSimulation();

      const first = findReport(model, "corr-first")!;
      const second = findReport(model, "corr-second")!;
      expect(first.id).not.toBe(second.id);
      expect(model.workspace.documents).toHaveLength(3);

      model.onSimulationCompleted({
        correlation_id: "corr-first",
        graph_id: "g1",
        experiment_id: "sim-first",
      });
      model.onSimulationCompleted({
        correlation_id: "corr-second",
        graph_id: "g1",
        experiment_id: "sim-second",
      });
      model.onSimulationReportReady(
        makeReportReply({ experiment_id: "sim-first" }),
      );
      model.onSimulationReportReady(
        makeReportReply({ experiment_id: "sim-second" }),
      );

      expect(first.reportData?.experiment_id).toBe("sim-first");
      expect(second.reportData?.experiment_id).toBe("sim-second");
    });
  });

  describe("runActiveOptimization", () => {
    it("submits simulation parameters only for the simulation-informed strategy", async () => {
      await model.workspace.openLoadedGraph(
        makeLoadedGraph({ nodes: [hostNode("host-1")] }),
        api,
      );
      model.workspace.onOptimizationParamsChange({
        strategy: "simulation_informed",
        budget: 25,
      });
      vi.mocked(api.runOptimization).mockResolvedValue({
        status: "accepted",
        graph_id: "g1",
        correlation_id: "corr-optimization",
      });

      await model.runActiveOptimization();

      expect(api.runOptimization).toHaveBeenCalledWith(
        "g1",
        expect.any(String),
        expect.objectContaining({
          strategy: "simulation_informed",
          budget: 25,
          simulation_params: expect.objectContaining({
            initial_foothold_node_id: "host-1",
          }),
        }),
      );
      expect(model.workspace.optimizationPending).toEqual({
        graphId: "g1",
        correlationId: "corr-optimization",
      });
    });

    it("allows only one optimization request while one is pending", async () => {
      await model.workspace.openLoadedGraph(makeLoadedGraph(), api);
      let resolve!: (value: {
        status: "accepted";
        graph_id: string;
        correlation_id: string;
      }) => void;
      vi.mocked(api.runOptimization).mockReturnValue(
        new Promise((res) => {
          resolve = res;
        }),
      );

      const first = model.runActiveOptimization();
      const second = model.runActiveOptimization();

      expect(model.workspace.isOptimizationPending).toBe(true);
      expect(api.runOptimization).toHaveBeenCalledTimes(1);

      resolve({
        status: "accepted",
        graph_id: "g1",
        correlation_id: model.workspace.optimizationPending!.correlationId,
      });
      await Promise.all([first, second]);
    });
  });

  describe("optimization events", () => {
    it("opens the optimized graph after a matching completion event", async () => {
      await model.workspace.openLoadedGraph(makeLoadedGraph(), api);
      vi.mocked(api.runOptimization).mockResolvedValue({
        status: "accepted",
        graph_id: "g1",
        correlation_id: "corr-optimization",
      });
      vi.mocked(api.openGraph).mockResolvedValue({
        status: "ok",
        graph: makeLoadedGraph({ id: "optimized-g1", title: "Optimized" }),
      });

      await model.runActiveOptimization();
      await model.onOptimizationCompleted({
        correlation_id: "corr-optimization",
        graph_id: "g1",
        optimized_graph_id: "optimized-g1",
      });

      expect(model.workspace.optimizationPending).toBeNull();
      expect(api.openGraph).toHaveBeenCalledWith("optimized-g1");
      expect(model.workspace.activeGraph?.loadedGraphId).toBe("optimized-g1");
    });

    it("clears a matching pending optimization and reports its failure", async () => {
      model.workspace.beginOptimization({
        graphId: "g1",
        correlationId: "corr-optimization",
      });

      model.onOptimizationFailed({
        correlation_id: "corr-optimization",
        graph_id: "g1",
        reason: "No eligible defenses.",
      });

      expect(model.workspace.optimizationPending).toBeNull();
      expect(model.workspace.statusMessage).toBe("No eligible defenses.");
    });
  });

  describe("onSimulationCompleted", () => {
    it("requests a report for matching correlation ID", () => {
      model.workspace.createPendingReport({
        graphId: "g1",
        correlationId: "corr-match",
        graphTitle: "Test",
      });

      model.onSimulationCompleted({
        correlation_id: "corr-match",
        graph_id: "g1",
        experiment_id: "sim-1",
      });

      const report = findReport(model, "corr-match")!;

      // Synchronous: complete() sets experimentId and status via load()
      expect(report.experimentId).toBe("sim-1");
      expect(report.status).toBe("loading");
      expect(api.requestSimulationReport).toHaveBeenCalledWith("sim-1", "g1");
    });

    it("ignores mismatched completion event", () => {
      model.workspace.createPendingReport({
        graphId: "g1",
        correlationId: "corr-abc",
        graphTitle: "Test",
      });

      model.onSimulationCompleted({
        correlation_id: "corr-mismatch",
        graph_id: "g2",
        experiment_id: "sim-2",
      });

      expect(api.requestSimulationReport).not.toHaveBeenCalled();
    });

    it("ignores a completion with a matching correlation ID for another graph", () => {
      model.workspace.createPendingReport({
        graphId: "g1",
        correlationId: "corr-match",
        graphTitle: "Test",
      });

      model.onSimulationCompleted({
        correlation_id: "corr-match",
        graph_id: "g2",
        experiment_id: "sim-2",
      });

      expect(api.requestSimulationReport).not.toHaveBeenCalled();
    });

    it("keeps an active report read when it completes", () => {
      const report = model.workspace.createPendingReport({
        graphId: "g1",
        correlationId: "corr-active",
        graphTitle: "Test",
      });
      report.markUnread();

      model.onSimulationCompleted({
        correlation_id: "corr-active",
        graph_id: "g1",
        experiment_id: "sim-active",
      });

      expect(report.hasUnread).toBe(false);
    });

    it("marks an inactive report unread when it completes", () => {
      const report = model.workspace.createPendingReport({
        graphId: "g1",
        correlationId: "corr-inactive",
        graphTitle: "Test",
      });
      model.workspace.createGraphDocument();

      model.onSimulationCompleted({
        correlation_id: "corr-inactive",
        graph_id: "g1",
        experiment_id: "sim-inactive",
      });

      expect(report.hasUnread).toBe(true);
    });
  });

  describe("onSimulationFailed", () => {
    it("sets report error for matching correlation ID", () => {
      model.workspace.createPendingReport({
        graphId: "g1",
        correlationId: "corr-fail",
        graphTitle: "Test",
      });

      model.onSimulationFailed({
        correlation_id: "corr-fail",
        graph_id: "g1",
        reason: "Simulation crashed",
      });

      const report = findReport(model, "corr-fail")!;
      expect(report.status).toBe("error");
      expect(report.errorReason).toBe("Simulation crashed");
    });

    it("marks an inactive failed report unread", () => {
      const report = model.workspace.createPendingReport({
        graphId: "g1",
        correlationId: "corr-inactive-failure",
        graphTitle: "Test",
      });
      model.workspace.createGraphDocument();

      model.onSimulationFailed({
        correlation_id: "corr-inactive-failure",
        graph_id: "g1",
        reason: "Simulation crashed",
      });

      expect(report.hasUnread).toBe(true);
    });

    it("ignores mismatched failure event", () => {
      model.workspace.createPendingReport({
        graphId: "g1",
        correlationId: "corr-abc",
        graphTitle: "Test",
      });

      model.onSimulationFailed({
        correlation_id: "corr-mismatch",
        graph_id: "g2",
        reason: "boom",
      });

      const report = findReport(model, "corr-abc")!;
      expect(report.status).toBe("pending");
      expect(report.errorReason).toBe("");
    });

    it("ignores a failure with a matching correlation ID for another graph", () => {
      model.workspace.createPendingReport({
        graphId: "g1",
        correlationId: "corr-abc",
        graphTitle: "Test",
      });

      model.onSimulationFailed({
        correlation_id: "corr-abc",
        graph_id: "g2",
        reason: "boom",
      });

      const report = findReport(model, "corr-abc")!;
      expect(report.status).toBe("pending");
      expect(report.errorReason).toBe("");
    });
  });
});
