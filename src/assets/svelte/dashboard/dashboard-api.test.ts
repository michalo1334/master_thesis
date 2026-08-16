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
      { strategy: "cvss", budget: 3, objective: "blast_radius" },
    );

    expect(result).toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "run_optimization_request",
      {
        request: {
          graph_revision_id: "r1",
          correlation_id: "corr-1",
          optimization_params: {
            strategy: "cvss",
            budget: 3,
            objective: "blast_radius",
          },
        },
      },
      expect.any(Function),
    );
  });

  it("sends the combined analysis workflow request", async () => {
    const reply = { status: "accepted" as const, workflow_id: "workflow-1" };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;

    await expect(
      createDashboardApi(live).runWorkflow(
        "r1",
        "corr-1",
        {
          initial_foothold_node_id: "host-1",
          monte_carlo_trials: 10,
          iterations_per_run: 10,
          max_attempts: 1,
          generate_seed: false,
          seed: 1,
        },
        { strategy: "cvss", budget: 3, objective: "blast_radius" },
      ),
    ).resolves.toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "run_workflow_request",
      {
        request: {
          template: "combined_analysis",
          graph_revision_id: "r1",
          correlation_id: "corr-1",
          simulation_params: expect.any(Object),
          optimization_params: {
            strategy: "cvss",
            budget: 3,
            objective: "blast_radius",
          },
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

  it("fetches the document catalog through the LiveView reply callback", async () => {
    const reply = { items: [] };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;

    await expect(
      createDashboardApi(live).fetchDocumentCatalog(),
    ).resolves.toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "fetch_document_catalog",
      {},
      expect.any(Function),
    );
  });

  it("requests an optimization report and fetches saved optimization runs", async () => {
    const reply = { runs: [] };
    const live = {
      pushEvent: vi.fn((event, _, onReply) => {
        if (event === "fetch_optimization_runs") onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;
    const api = createDashboardApi(live);

    api.requestReport({
      type: "optimization",
      documentId: "document-1",
      reportId: "optimization-1",
      graphRevisionId: "r1",
    });
    await expect(api.fetchOptimizationRuns(["r1"])).resolves.toEqual(reply);

    expect(live.pushEvent).toHaveBeenNthCalledWith(
      1,
      "fetch_optimization_report",
      {
        document_id: "document-1",
        optimization_id: "optimization-1",
        graph_revision_id: "r1",
      },
    );
    expect(live.pushEvent).toHaveBeenNthCalledWith(
      2,
      "fetch_optimization_runs",
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

  it("sends folder requests through LiveView reply callbacks", async () => {
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply({ status: "ok" }, 1);
        return 1;
      }),
    } as unknown as LiveServer;
    const api = createDashboardApi(live);

    await api.createFolder("Threat models");
    await api.deleteFolder("folder-1");
    await api.moveGraphToFolder("graph-1", null);

    expect(live.pushEvent).toHaveBeenNthCalledWith(
      1,
      "create_folder",
      { name: "Threat models" },
      expect.any(Function),
    );
    expect(live.pushEvent).toHaveBeenNthCalledWith(
      2,
      "delete_folder",
      { folder_id: "folder-1" },
      expect.any(Function),
    );
    expect(live.pushEvent).toHaveBeenNthCalledWith(
      3,
      "move_graph_to_folder",
      { graph_id: "graph-1", folder_id: null },
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

  it("fetches the graph projection for a revision", async () => {
    const reply = {
      status: "ok" as const,
      segments: [{ id: "segment-1" }],
      hosts: [{ id: "host-1" }],
      policy_links: [
        { id: "link-1", from_id: "segment-1", to_id: "segment-2" },
      ],
      operational_flows: [
        { id: "flow-1", from_id: "host-1", to_id: "service-1" },
      ],
    };
    const live = {
      pushEvent: vi.fn((_, __, onReply) => {
        onReply(reply, 1);
        return 1;
      }),
    } as unknown as LiveServer;

    const result = await createDashboardApi(live).fetchGraphProjection("r1");

    expect(result).toEqual(reply);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "fetch_graph_projection",
      { graph_revision_id: "r1" },
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
