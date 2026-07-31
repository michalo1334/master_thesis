import { describe, expect, it, vi } from "vitest";
import { createDashboardApi, type LiveServer } from "./dashboard-api";

describe("DashboardApi", () => {
  it("sends the optimization request and returns the reply", async () => {
    const reply = {
      status: "accepted" as const,
      graph_id: "g1",
      correlation_id: "corr-1",
    };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;

    const result = await createDashboardApi(live).runOptimization(
      "g1",
      "corr-1",
      { strategy: "cvss", budget: 3 },
    );

    expect(result).toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "run_optimization_request",
      {
        request: {
          graph_id: "g1",
          correlation_id: "corr-1",
          optimization_params: { strategy: "cvss", budget: 3 },
        },
      },
      expect.any(Function),
    );
  });

  it("fetches experiments through the LiveView reply callback", async () => {
    const reply = { experiments: [] };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;

    const result = await createDashboardApi(live).fetchExperiments(["g1"]);

    expect(result).toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "fetch_experiments",
      { graph_ids: ["g1"] },
      expect.any(Function),
    );
  });
});
