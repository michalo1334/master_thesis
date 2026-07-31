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

  it("fetches graph connectivity through the LiveView reply callback", async () => {
    const reply = {
      rules: [
        {
          from_type: "Host" as const,
          to_type: "Service" as const,
          relationship_type: "Runs" as const,
        },
      ],
    };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;

    const result = await createDashboardApi(live).fetchGraphConnectivity();

    expect(result).toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "fetch_graph_connectivity",
      {},
      expect.any(Function),
    );
  });

  it("creates node drafts through the LiveView reply callback", async () => {
    const reply = { status: "ok" as const };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;
    const payload = { node_type: "Host" as const, x_pos: 30, y_pos: 40 };

    await expect(
      createDashboardApi(live).createNodeDraft(payload),
    ).resolves.toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "create_node_draft",
      payload,
      expect.any(Function),
    );
  });

  it("creates connection drafts through the LiveView reply callback", async () => {
    const reply = { status: "ok" as const };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;
    const payload = {
      relationship_type: "Runs" as const,
      source_id: "source",
      source_type: "Host" as const,
      source_is_from: true,
      target_id: "target",
      target_type: "Service" as const,
    };

    await expect(
      createDashboardApi(live).createConnectionDraft(payload as never),
    ).resolves.toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "create_connection_draft",
      payload,
      expect.any(Function),
    );
  });
});
