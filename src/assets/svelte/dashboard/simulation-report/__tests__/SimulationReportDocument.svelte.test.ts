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
    multi_state_id: "sim-1",
    simulation_count: 10,
    total_runtime_ms: 500,
    ...overrides,
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

describe("SimulationReportDocument", () => {
  it("does not let an earlier successful load overwrite a newer error", async () => {
    const first = deferred<FetchSimulationReportReply | { status: string }>();
    const second = deferred<FetchSimulationReportReply | { status: string }>();
    const api = {
      fetchSimulationReport: vi
        .fn()
        .mockReturnValueOnce(first.promise)
        .mockReturnValueOnce(second.promise),
    } as unknown as DashboardApi;
    const document = new SimulationReportDocument("Topology", "g1");

    const firstLoad = document.load(api, "sim-first", "g1");
    const secondLoad = document.load(api, "sim-second", "g1");
    second.resolve({ status: "not_found" });
    await secondLoad;
    first.resolve(makeReport({ multi_state_id: "sim-first" }));
    await firstLoad;

    expect(document.simulationId).toBe("sim-second");
    expect(document.status).toBe("error");
    expect(document.errorReason).toBe("not_found");
    expect(document.reportData).toBeNull();
  });

  it("does not let an earlier rejected load overwrite a newer report", async () => {
    const first = deferred<FetchSimulationReportReply | { status: string }>();
    const second = deferred<FetchSimulationReportReply | { status: string }>();
    const api = {
      fetchSimulationReport: vi
        .fn()
        .mockReturnValueOnce(first.promise)
        .mockReturnValueOnce(second.promise),
    } as unknown as DashboardApi;
    const document = new SimulationReportDocument("Topology", "g1");

    const firstLoad = document.load(api, "sim-first", "g1");
    const secondLoad = document.load(api, "sim-second", "g1");
    second.resolve(makeReport({ multi_state_id: "sim-second" }));
    await secondLoad;
    first.reject(new Error("offline"));
    await firstLoad;

    expect(document.simulationId).toBe("sim-second");
    expect(document.status).toBe("loaded");
    expect(document.errorReason).toBe("");
    expect(document.reportData?.multi_state_id).toBe("sim-second");
  });

  it("invalidates an in-flight load when a report becomes pending", async () => {
    const request = deferred<FetchSimulationReportReply | { status: string }>();
    const api = {
      fetchSimulationReport: vi.fn().mockReturnValue(request.promise),
    } as unknown as DashboardApi;
    const document = new SimulationReportDocument("Topology", "g1");

    const load = document.load(api, "sim-first", "g1");
    document.markPending("corr-next");
    request.resolve(makeReport({ multi_state_id: "sim-first" }));
    await load;

    expect(document.simulationId).toBeNull();
    expect(document.status).toBe("pending");
    expect(document.reportData).toBeNull();
    expect(document.errorReason).toBe("");
  });
});
