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
      action_stats: [],
      blast_radius_distribution: [],
      convergence: [],
    },
    graph_id: "g1",
    graph_title: "Test Graph",
    graph_version_at_sim: 1,
    iteration_count: 100,
    kpis: [],
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
