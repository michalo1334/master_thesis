import { describe, expect, it, vi } from "vitest";
import { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import { OptimizationReportDocument } from "./OptimizationReportDocument.svelte";
import type { DashboardApi } from "../dashboard-api";

describe("OptimizationReportDocument", () => {
  const createDocument = () =>
    new OptimizationReportDocument({
      graphId: "g1",
      graphRevisionId: "r1",
      graphTitle: "Topology",
      correlationId: "corr-1",
      strategy: "simulation_informed",
      budget: 2,
    });
  const api = () =>
    ({ requestOptimizationReport: vi.fn() }) as unknown as DashboardApi;

  it("keeps progress scoped to a pending report", () => {
    const document = createDocument();
    document.setProgress(2, 5, "Scoring defenses");

    expect(document.completedSteps).toBe(2);
    expect(document.totalSteps).toBe(5);
    expect(document.phase).toBe("Scoring defenses");
  });

  it("requests persisted completion data and exposes, but does not invoke, the open callback", () => {
    const document = createDocument();
    const openOptimizedGraph = vi.fn().mockResolvedValue(true);
    const dashboardApi = api();

    document.complete(
      dashboardApi,
      {
        correlation_id: "corr-1",
        graph_id: "g1",
        graph_revision_id: "r1",
        output_graph_revision_id: "optimized-r1",
        optimization_id: "optimization-1",
      },
      openOptimizedGraph,
    );

    expect(document.status).toBe("loading");
    expect(document.optimizationId).toBe("optimization-1");
    expect(dashboardApi.requestOptimizationReport).toHaveBeenCalledWith(
      "optimization-1",
      "r1",
    );
    document.setReportData({
      optimization_id: "optimization-1",
      graph_id: "g1",
      graph_title: "Topology",
      graph_revision_id: "r1",
      report: {
        strategy: "simulation_informed",
        objective: "blast_radius",
        requested_budget: 2,
        used_budget: 1,
        runtime_ms: 25,
        actions: [
          {
            id: "patch-1",
            label: "Patch CVE-1",
            kind: "patch_vulnerability",
            cost: 1,
          },
        ],
      },
    });

    expect(document.status).toBe("loaded");
    expect(document.reportData?.actions).toHaveLength(1);
    expect(document.analysis?.strategy).toBe("simulation_informed");
    expect(openOptimizedGraph).not.toHaveBeenCalled();
  });

  it("loads the graph diff only when requested", async () => {
    const document = createDocument();
    const graph = {
      id: "g1",
      title: "Topology",
      revision_id: "r1",
      parent_revision_id: null,
      revision_kind: "original",
      revision_number: 1,
      nodes: [],
      edges: [],
    };
    const graphDiff = new GraphDiffDocument(
      graph,
      { revisionId: "optimized-r1", title: "Optimized graph" },
      {
        graph,
        node_status: [],
        edge_status: [],
        node_counts: { added: 0, removed: 0, unchanged: 0 },
        edge_counts: { added: 0, removed: 0, unchanged: 0 },
      },
    );
    const createGraphDiff = vi.fn().mockResolvedValue(graphDiff);
    const dashboardApi = api();

    document.complete(
      dashboardApi,
      {
        correlation_id: "corr-1",
        graph_id: "g1",
        graph_revision_id: "r1",
        output_graph_revision_id: "optimized-r1",
        optimization_id: "optimization-1",
      },
      vi.fn().mockResolvedValue(true),
      createGraphDiff,
    );

    expect(createGraphDiff).not.toHaveBeenCalled();
    await expect(document.loadGraphDiff()).resolves.toBe(true);
    expect(document.graphDiff).toBe(graphDiff);
    expect(createGraphDiff).toHaveBeenCalledOnce();
    await expect(document.loadGraphDiff()).resolves.toBe(true);
    expect(createGraphDiff).toHaveBeenCalledOnce();
  });
});
