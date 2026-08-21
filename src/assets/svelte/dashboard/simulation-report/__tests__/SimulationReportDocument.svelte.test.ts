import { describe, expect, it, vi } from "vitest";
import { SimulationReportDocument } from "../SimulationReportDocument.svelte";
import type { DashboardApi } from "../../dashboard-api";
import type { FetchSimulationReportReply } from "../../contract";

function makeReport(
  overrides: Partial<FetchSimulationReportReply> = {},
): FetchSimulationReportReply {
  return {
    capability_statuses: [],
    charts: {
      action_success: [],
      capability_impact: [],
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
    feasible: true,
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
      expected_mission_impact: 2,
      median_mission_impact: 2,
      mission_impact_p95: 4,
      mission_impact_p99: 5,
      min_mission_impact: 1,
      max_mission_impact: 5,
      mission_impact_variance: 1.2,
    },
    experiment_id: "sim-1",
    run_count: 10,
    total_runtime_ms: 500,
    ...overrides,
  };
}

describe("SimulationReportDocument", () => {
  it("requests a report with its document ID without awaiting a reply", () => {
    const api = {
      requestSimulationReport: vi.fn(),
    };
    const document = new SimulationReportDocument("Topology", "g1", "r1");

    document.load(api as unknown as DashboardApi, document.id, "sim-1");

    expect(document.status).toBe("loading");
    expect(api.requestSimulationReport).toHaveBeenCalledWith(
      document.id,
      "sim-1",
    );
  });

  it("applies a report only for the active experiment", () => {
    const api = {
      requestSimulationReport: vi.fn(),
    };
    const document = new SimulationReportDocument("Topology", "g1", "r1");

    document.load(api as unknown as DashboardApi, document.id, "sim-current");
    document.setReportData(makeReport({ experiment_id: "sim-stale" }));

    expect(document.status).toBe("loading");
    expect(document.reportData).toBeNull();
  });

  it("loads a matching report received through the LiveView event", () => {
    const api = {
      requestSimulationReport: vi.fn(),
    };
    const document = new SimulationReportDocument("Topology", "g1", "r1");

    document.load(api as unknown as DashboardApi, document.id, "sim-1");
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
});
