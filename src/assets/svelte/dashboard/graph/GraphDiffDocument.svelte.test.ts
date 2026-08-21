import { describe, expect, it, vi } from "vitest";
import { GraphDiffDocument } from "./GraphDiffDocument.svelte";
import type { DashboardApi } from "../dashboard-api";
import type { DashboardRecoveryContext } from "../workspace/recovery-context";

describe("GraphDiffDocument", () => {
  it("hydrates both graph titles from revision IDs", async () => {
    const document = GraphDiffDocument.fromPersisted(
      {
        kind: "graph-diff",
        ids: { baseRevisionId: "base", comparisonRevisionId: "comparison" },
        title: "Saved comparison",
      },
      {} as DashboardRecoveryContext,
    )!;
    const api = {
      openGraph: vi.fn((revisionId: string) =>
        Promise.resolve({
          status: "ok" as const,
          graph: {
            id: revisionId,
            title: revisionId === "base" ? "Base" : "Comparison",
            revision_id: revisionId,
            nodes: [],
            edges: [],
          },
        }),
      ),
      compareGraphs: vi.fn().mockResolvedValue({
        status: "ok",
        result: {
          graph: { id: "base", title: "Base", nodes: [], edges: [] },
          node_status: [],
          edge_status: [],
          node_counts: { added: 0, removed: 0, unchanged: 0 },
          edge_counts: { added: 0, removed: 0, unchanged: 0 },
        },
      }),
    } as unknown as DashboardApi;

    document.recover({ api } as DashboardRecoveryContext);

    await vi.waitFor(() => expect(document.status).toBe("loaded"));
    expect(api.openGraph).toHaveBeenNthCalledWith(1, "base");
    expect(api.openGraph).toHaveBeenNthCalledWith(2, "comparison");
    expect(document.title).toBe("Base compared with Comparison");
  });
});
