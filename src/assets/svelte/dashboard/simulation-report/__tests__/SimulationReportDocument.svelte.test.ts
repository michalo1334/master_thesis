import { describe, expect, it, vi } from "vitest";
import { SimulationReportDocument } from "../SimulationReportDocument.svelte";
import type { DashboardApi } from "../../dashboard-api";
import type { FetchSimulationReportReply } from "../../contract";

function makeReport(
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
    graph: {
      id: "g1",
      title: "Topology",
      revision_id: "r1",
      parent_revision_id: null,
      revision_kind: "original",
      revision_number: 1,
      nodes: [],
      edges: [],
    },
    graph_id: "g1",
    graph_revision_id: "r1",
    graph_title: "Topology",
    iteration_count: 100,
    operational_flows: [],
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

describe("SimulationReportDocument", () => {
  it("requests a report without awaiting its LiveView reply", () => {
    const api = {
      requestSimulationReport: vi.fn(),
    } as unknown as DashboardApi;
    const document = new SimulationReportDocument("Topology", "g1", "r1");

    document.load(api, "sim-1", "r1");

    expect(document.status).toBe("loading");
    expect(api.requestSimulationReport).toHaveBeenCalledWith("sim-1", "r1");
  });

  it("applies a report only for the active experiment", () => {
    const api = {
      requestSimulationReport: vi.fn(),
    } as unknown as DashboardApi;
    const document = new SimulationReportDocument("Topology", "g1", "r1");

    document.load(api, "sim-current", "r1");
    document.setReportData(makeReport({ experiment_id: "sim-stale" }));

    expect(document.status).toBe("loading");
    expect(document.reportData).toBeNull();
  });

  it("loads a matching report received through the LiveView event", () => {
    const api = {
      requestSimulationReport: vi.fn(),
    } as unknown as DashboardApi;
    const document = new SimulationReportDocument("Topology", "g1", "r1");

    document.load(api, "sim-1", "r1");
    document.setReportData(makeReport());

    expect(document.status).toBe("loaded");
    expect(document.reportData?.experiment_id).toBe("sim-1");
  });

  it("keeps heatmap selection local and clears it with a new layout", () => {
    const document = new SimulationReportDocument("Topology", "g1", "r1");

    document.markReady("sim-1");
    document.selectHeatmapNode("node-1");
    expect(document.heatmapSelectedNodeId).toBe("node-1");
    expect(document.heatmapSelectedEdgeId).toBeUndefined();

    document.selectHeatmapEdge("edge-1");
    expect(document.heatmapSelectedNodeId).toBeUndefined();
    expect(document.heatmapSelectedEdgeId).toBe("edge-1");

    document.setReportData(makeReport());

    expect(document.heatmapSelectedNodeId).toBeUndefined();
    expect(document.heatmapSelectedEdgeId).toBeUndefined();
  });

  it("explains when the topology changed after a simulation", () => {
    const document = new SimulationReportDocument("Topology", "g1", "r1");

    document.markError("graph_version_mismatch");

    expect(document.errorReason).toBe(
      "The topology changed after this simulation ran. Run the simulation again.",
    );
  });
});
