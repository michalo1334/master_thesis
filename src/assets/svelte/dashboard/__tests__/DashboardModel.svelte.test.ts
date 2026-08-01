import { describe, it, expect, beforeEach, vi } from "vitest";
import { DashboardModel } from "../DashboardModel.svelte";
import type { DashboardApi } from "../dashboard-api";
import type {
  FetchSimulationReportReply,
  LoadedGraph,
  SaveGraphReply,
} from "../contract";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";

function makeMockApi(overrides: Partial<DashboardApi> = {}): DashboardApi {
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
    ...overrides,
  };
}

function makeLoadedGraph(overrides: Partial<LoadedGraph> = {}): LoadedGraph {
  return {
    id: "g1",
    title: "Test Graph",
    lock_version: 1,
    parent_id: null,
    tags: ["original"],
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
      expect(api.saveGraph).not.toHaveBeenCalled();
    });

    it("saves a dirty graph before starting simulation", async () => {
      const graph = makeLoadedGraph({ nodes: [hostNode("host-1")] });
      await model.workspace.openLoadedGraph(graph, api);
      model.workspace.activeGraph!.addNode(hostNode("host-2"));
      vi.mocked(api.saveGraph).mockResolvedValue({
        status: "ok",
        graph: makeLoadedGraph({
          lock_version: 2,
          nodes: [hostNode("host-1"), hostNode("host-2")],
        }),
      });
      vi.mocked(api.runSimulation).mockResolvedValue({
        status: "accepted",
        graph_id: "g1",
        correlation_id: "corr-saved",
      });

      await model.runActiveSimulation();

      expect(api.saveGraph).toHaveBeenCalledOnce();
      expect(api.runSimulation).toHaveBeenCalledOnce();
      expect(vi.mocked(api.saveGraph).mock.invocationCallOrder[0]).toBeLessThan(
        vi.mocked(api.runSimulation).mock.invocationCallOrder[0]!,
      );
      expect(findReport(model, "corr-saved")).toBeDefined();
    });

    it("does not start simulation when the graph changes during its save", async () => {
      const graph = makeLoadedGraph({ nodes: [hostNode("host-1")] });
      await model.workspace.openLoadedGraph(graph, api);
      model.workspace.activeGraph!.addNode(hostNode("host-2"));

      let resolveSave!: (reply: SaveGraphReply) => void;
      vi.mocked(api.saveGraph).mockImplementation(
        () => new Promise<SaveGraphReply>((resolve) => (resolveSave = resolve)),
      );

      const simulation = model.runActiveSimulation();
      model.workspace.activeGraph!.addNode(hostNode("host-3"));
      resolveSave({
        status: "ok",
        graph: makeLoadedGraph({
          lock_version: 2,
          nodes: [hostNode("host-1"), hostNode("host-2")],
        }),
      });

      await simulation;

      expect(api.runSimulation).not.toHaveBeenCalled();
      expect(model.workspace.activeGraph!.isDirty).toBe(true);
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

    it("does not start operations when saving a dirty graph fails", async () => {
      await model.workspace.openLoadedGraph(
        makeLoadedGraph({ nodes: [hostNode("host-1")] }),
        api,
      );
      model.workspace.activeGraph!.addNode(hostNode("host-2"));
      vi.mocked(api.saveGraph).mockResolvedValue({ status: "stale" });

      await model.runActiveSimulation();
      await model.runActiveOptimization();

      expect(api.runSimulation).not.toHaveBeenCalled();
      expect(api.runOptimization).not.toHaveBeenCalled();
      expect(
        model.workspace.documents.filter(
          (document) => document.kind === "simulation-report",
        ),
      ).toEqual([]);
      expect(
        model.workspace.documents.filter(
          (document) => document.kind === "optimization-report",
        ),
      ).toEqual([]);
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
    it("saves a dirty graph before creating and starting an optimization", async () => {
      const graph = makeLoadedGraph({ nodes: [hostNode("host-1")] });
      await model.workspace.openLoadedGraph(graph, api);
      model.workspace.activeGraph!.addNode(hostNode("host-2"));
      vi.mocked(api.saveGraph).mockResolvedValue({
        status: "ok",
        graph: makeLoadedGraph({
          lock_version: 2,
          nodes: [hostNode("host-1"), hostNode("host-2")],
        }),
      });
      vi.mocked(api.runOptimization).mockImplementation(
        async (_graphId, correlationId) => ({
          status: "accepted",
          graph_id: "g1",
          correlation_id: correlationId,
        }),
      );

      await model.runActiveOptimization();

      expect(api.saveGraph).toHaveBeenCalledOnce();
      expect(api.runOptimization).toHaveBeenCalledOnce();
      expect(vi.mocked(api.saveGraph).mock.invocationCallOrder[0]).toBeLessThan(
        vi.mocked(api.runOptimization).mock.invocationCallOrder[0]!,
      );
      expect(
        model.workspace.documents.some(
          (document) => document.kind === "optimization-report",
        ),
      ).toBe(true);
    });

    it.each([
      "cvss",
      "simulation_informed",
      "topology_segmentation",
      "simulated_annealing",
    ] as const)("submits simulation parameters for %s", async (strategy) => {
      await model.workspace.openLoadedGraph(
        makeLoadedGraph({ nodes: [hostNode("host-1")] }),
        api,
      );
      model.workspace.onOptimizationParamsChange({
        strategy,
        budget: 25,
      });
      vi.mocked(api.runOptimization).mockImplementation(
        async (_graphId, correlationId) => ({
          status: "accepted",
          graph_id: "g1",
          correlation_id: correlationId,
        }),
      );

      await model.runActiveOptimization();

      expect(api.runOptimization).toHaveBeenCalledWith(
        "g1",
        expect.any(String),
        expect.objectContaining({
          strategy,
          budget: 25,
          simulation_params: expect.objectContaining({
            initial_foothold_node_id: "host-1",
          }),
        }),
      );
      const correlationId = vi.mocked(api.runOptimization).mock.calls[0]![1];
      expect(
        model.workspace.findOptimizationReport(correlationId, "g1"),
      ).toMatchObject({ correlationId, graphId: "g1", status: "pending" });
    });

    it("snapshots parameters and creates the report before the reply", async () => {
      await model.workspace.openLoadedGraph(
        makeLoadedGraph({ nodes: [hostNode("host-1")] }),
        api,
      );
      model.workspace.onOptimizationParamsChange({
        budget: 25,
        simulation_params: { monte_carlo_trials: 100 },
      });

      let resolve!: () => void;
      vi.mocked(api.runOptimization).mockImplementation(
        (_graphId, correlationId) =>
          new Promise((complete) => {
            resolve = () =>
              complete({
                status: "accepted",
                graph_id: "g1",
                correlation_id: correlationId,
              });
          }),
      );

      const optimization = model.runActiveOptimization();
      const correlationId = vi.mocked(api.runOptimization).mock.calls[0]![1];
      const submitted = vi.mocked(api.runOptimization).mock.calls[0]![2];
      const report = model.workspace.findOptimizationReport(
        correlationId,
        "g1",
      );

      expect(report?.status).toBe("pending");
      model.workspace.onOptimizationParamsChange({
        budget: 50,
        simulation_params: { monte_carlo_trials: 200 },
      });
      expect(submitted).toMatchObject({
        budget: 25,
        simulation_params: { monte_carlo_trials: 100 },
      });

      resolve();
      await optimization;
    });

    it("routes concurrent optimization events to reports by correlation ID", async () => {
      await model.workspace.openLoadedGraph(makeLoadedGraph(), api);
      const graphDocumentId = model.workspace.activeGraph!.id;
      let resolveFirst!: () => void;
      let resolveSecond!: () => void;
      vi.mocked(api.runOptimization)
        .mockImplementationOnce(
          (_graphId, correlationId) =>
            new Promise((complete) => {
              resolveFirst = () =>
                complete({
                  status: "accepted",
                  graph_id: "g1",
                  correlation_id: correlationId,
                });
            }),
        )
        .mockImplementationOnce(
          (_graphId, correlationId) =>
            new Promise((complete) => {
              resolveSecond = () =>
                complete({
                  status: "accepted",
                  graph_id: "g1",
                  correlation_id: correlationId,
                });
            }),
        );

      const first = model.runActiveOptimization();
      model.workspace.selectDocument(graphDocumentId);
      const second = model.runActiveOptimization();

      expect(api.runOptimization).toHaveBeenCalledTimes(2);
      const firstCorrelationId = vi.mocked(api.runOptimization).mock
        .calls[0]![1];
      const secondCorrelationId = vi.mocked(api.runOptimization).mock
        .calls[1]![1];
      const firstReport = model.workspace.findOptimizationReport(
        firstCorrelationId,
        "g1",
      )!;
      const secondReport = model.workspace.findOptimizationReport(
        secondCorrelationId,
        "g1",
      )!;
      expect(firstReport.id).not.toBe(secondReport.id);
      expect(firstReport.status).toBe("pending");
      expect(secondReport.status).toBe("pending");

      resolveFirst();
      await first;
      resolveSecond();
      await second;

      model.onOptimizationProgress({
        correlation_id: firstCorrelationId,
        graph_id: "g1",
        completed_steps: 2,
        total_steps: 4,
        phase: "evaluating",
      });
      model.onOptimizationFailed({
        correlation_id: secondCorrelationId,
        graph_id: "g1",
        reason: "No eligible defenses.",
      });
      model.onOptimizationCompleted({
        correlation_id: firstCorrelationId,
        graph_id: "g1",
        optimized_graph_id: "optimized-g1",
        report: {
          strategy: "cvss",
          requested_budget: 1,
          used_budget: 1,
          runtime_ms: 12,
          actions: [],
        },
      });

      expect(firstReport.completedSteps).toBe(2);
      expect(firstReport.status).toBe("completed");
      expect(secondReport.status).toBe("error");
      expect(secondReport.errorReason).toBe("No eligible defenses.");
    });

    it("keeps rejected reports as errors", async () => {
      await model.workspace.openLoadedGraph(makeLoadedGraph(), api);
      vi.mocked(api.runOptimization).mockImplementation(
        async (_graphId, correlationId) => ({
          status: "rejected",
          graph_id: "g1",
          correlation_id: correlationId,
          reason: "Server busy",
        }),
      );

      await model.runActiveOptimization();

      const report = model.workspace.documents.find(
        (document) => document.kind === "optimization-report",
      );
      expect(report?.status).toBe("error");
      expect(report?.errorReason).toBe("Server busy");
    });

    it("keeps network-failed reports as errors", async () => {
      await model.workspace.openLoadedGraph(makeLoadedGraph(), api);
      vi.mocked(api.runOptimization).mockRejectedValue(new Error("offline"));

      await model.runActiveOptimization();

      const report = model.workspace.documents.find(
        (document) => document.kind === "optimization-report",
      );
      expect(report?.status).toBe("error");
      expect(report?.errorReason).toBe("Optimization failed.");
    });
  });

  describe("optimization events", () => {
    it("keeps the optimized graph closed until the report callback opens it", async () => {
      await model.workspace.openLoadedGraph(makeLoadedGraph(), api);
      vi.mocked(api.runOptimization).mockImplementation(
        async (_graphId, correlationId) => ({
          status: "accepted",
          graph_id: "g1",
          correlation_id: correlationId,
        }),
      );
      vi.mocked(api.openGraph).mockResolvedValue({
        status: "ok",
        graph: makeLoadedGraph({ id: "optimized-g1", title: "Optimized" }),
      });

      await model.runActiveOptimization();
      const correlationId = vi.mocked(api.runOptimization).mock.calls[0]![1];
      model.onOptimizationCompleted({
        correlation_id: correlationId,
        graph_id: "g1",
        optimized_graph_id: "optimized-g1",
        report: {
          strategy: "cvss",
          requested_budget: 1,
          used_budget: 1,
          runtime_ms: 12,
          actions: [],
        },
      });

      const report = model.workspace.findOptimizationReport(
        correlationId,
        "g1",
      )!;
      expect(api.openGraph).not.toHaveBeenCalled();

      await report.openOptimizedGraph?.();

      expect(api.openGraph).toHaveBeenCalledWith("optimized-g1");
      expect(model.workspace.activeGraph?.loadedGraphId).toBe("optimized-g1");
    });

    it("reports a matching optimization failure", async () => {
      const report = model.workspace.createPendingOptimizationReport({
        graphId: "g1",
        correlationId: "corr-optimization",
        graphTitle: "Topology",
        strategy: "cvss",
        budget: 1,
      });
      model.onOptimizationFailed({
        correlation_id: "corr-optimization",
        graph_id: "g1",
        reason: "No eligible defenses.",
      });

      expect(report.status).toBe("error");
      expect(report.errorReason).toBe("No eligible defenses.");
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
