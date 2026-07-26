import { describe, expect, it, vi } from "vitest";
import { SimulationReportDocument } from "../SimulationReportDocument.svelte";
import type { DashboardApi } from "../../dashboard-api";
import type { FetchSimulationReportReply } from "../../contract";

function makeReport(
  overrides: Partial<FetchSimulationReportReply> = {},
): FetchSimulationReportReply {
  return {
    charts: {
      action_stats: [],
      blast_radius_distribution: [],
      convergence: [],
    },
    graph_id: "g1",
    graph_title: "Topology",
    graph_version_at_sim: 1,
    iteration_count: 100,
    kpis: [],
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
