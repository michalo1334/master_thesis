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
      histogram: [],
    },
    graph_id: "g1",
    graph_title: "Topology",
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

describe("SimulationReportDocument", () => {
  it("requests a report without awaiting its LiveView reply", () => {
    const api = {
      requestSimulationReport: vi.fn(),
    } as unknown as DashboardApi;
    const document = new SimulationReportDocument("Topology", "g1");

    document.load(api, "sim-1", "g1");

    expect(document.status).toBe("loading");
    expect(api.requestSimulationReport).toHaveBeenCalledWith("sim-1", "g1");
  });

  it("applies a report only for the active experiment", () => {
    const api = {
      requestSimulationReport: vi.fn(),
    } as unknown as DashboardApi;
    const document = new SimulationReportDocument("Topology", "g1");

    document.load(api, "sim-current", "g1");
    document.setReportData(makeReport({ experiment_id: "sim-stale" }));

    expect(document.status).toBe("loading");
    expect(document.reportData).toBeNull();
  });

  it("loads a matching report received through the LiveView event", () => {
    const api = {
      requestSimulationReport: vi.fn(),
    } as unknown as DashboardApi;
    const document = new SimulationReportDocument("Topology", "g1");

    document.load(api, "sim-1", "g1");
    document.setReportData(makeReport());

    expect(document.status).toBe("loaded");
    expect(document.reportData?.experiment_id).toBe("sim-1");
  });
});
