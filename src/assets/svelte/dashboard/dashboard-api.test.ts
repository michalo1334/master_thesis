import { describe, expect, it, vi } from "vitest";
import { createDashboardApi, type LiveServer } from "./dashboard-api";
import type { LoadedGraph } from "./contract";

describe("DashboardApi", () => {
  it("sends only the save contract fields", async () => {
    const reply = { status: "ok" as const };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;
    const graph: LoadedGraph = {
      id: "g1",
      revision_id: "r1",
      parent_revision_id: "r0",
      revision_kind: "original",
      revision_number: 1,
      title: "Graph",
      nodes: [],
      edges: [],
    };

    await expect(createDashboardApi(live).saveGraph(graph)).resolves.toEqual(
      reply,
    );
    expect(live.pushEvent).toHaveBeenCalledWith(
      "save_graph",
      {
        graph: {
          id: "g1",
          revision_id: "r1",
          title: "Graph",
          nodes: [],
          edges: [],
        },
      },
      expect.any(Function),
    );
  });

  it("rejects saves without a revision id", async () => {
    const live = { pushEvent: vi.fn() } as unknown as LiveServer;
    const graph: LoadedGraph = {
      id: "g1",
      title: "Graph",
      nodes: [],
      edges: [],
    };

    await expect(createDashboardApi(live).saveGraph(graph)).resolves.toEqual({
      status: "invalid_graph",
    });
    expect(live.pushEvent).not.toHaveBeenCalled();
  });

  it("sends the optimization request and returns the reply", async () => {
    const reply = {
      status: "accepted" as const,
      graph_revision_id: "r1",
      correlation_id: "corr-1",
    };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;

    const result = await createDashboardApi(live).runOptimization(
      "r1",
      "corr-1",
      { strategy: "cvss", budget: 3 },
    );

    expect(result).toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "run_optimization_request",
      {
        request: {
          graph_revision_id: "r1",
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

    const result = await createDashboardApi(live).fetchExperiments(["r1"]);

    expect(result).toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "fetch_experiments",
      { graph_revision_ids: ["r1"] },
      expect.any(Function),
    );
  });

  it("sends graph comparisons and returns the server result", async () => {
    const baseGraph: LoadedGraph = {
      id: "base",
      title: "Base",
      revision_id: "base-r1",
      parent_revision_id: null,
      revision_kind: "original",
      revision_number: 1,
      nodes: [],
      edges: [],
    };
    const reply = {
      status: "ok" as const,
      result: {
        graph: baseGraph,
        node_status: [],
        edge_status: [],
        node_counts: { added: 0, removed: 0, unchanged: 0 },
        edge_counts: { added: 0, removed: 0, unchanged: 0 },
      },
    };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;

    await expect(
      createDashboardApi(live).compareGraphs("base-r1", "comparison-r1"),
    ).resolves.toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "compare_graphs",
      { base_revision_id: "base-r1", comparison_revision_id: "comparison-r1" },
      expect.any(Function),
    );
  });

  it("sets a graph revision favorite", async () => {
    const reply = { status: "ok" as const, favorite: true };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;

    await expect(
      createDashboardApi(live).setGraphRevisionFavorite("r1", true),
    ).resolves.toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "set_graph_revision_favorite",
      { graph_revision_id: "r1", favorite: true },
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
