import { describe, expect, it, vi } from "vitest";
import { OptimizationReportDocument } from "./OptimizationReportDocument.svelte";

describe("OptimizationReportDocument", () => {
  const createDocument = () =>
    new OptimizationReportDocument({
      graphId: "g1",
      graphTitle: "Topology",
      correlationId: "corr-1",
      strategy: "simulation_informed",
      budget: 2,
    });

  it("keeps progress scoped to a pending report", () => {
    const document = createDocument();
    document.setProgress(2, 5, "Scoring defenses");

    expect(document.completedSteps).toBe(2);
    expect(document.totalSteps).toBe(5);
    expect(document.phase).toBe("Scoring defenses");
  });

  it("stores completion data and exposes, but does not invoke, the open callback", () => {
    const document = createDocument();
    const openOptimizedGraph = vi.fn().mockResolvedValue(true);

    document.complete(
      {
        correlation_id: "corr-1",
        graph_id: "g1",
        optimized_graph_id: "optimized-g1",
        report: {
          strategy: "simulation_informed",
          requested_budget: 2,
          used_budget: 1,
          runtime_ms: 25,
          actions: [
            {
              id: "patch-1",
              label: "Patch CVE-1",
              kind: "patch_vulnerability",
              cost: 1,
            },
          ],
        },
      },
      openOptimizedGraph,
    );

    expect(document.status).toBe("completed");
    expect(document.reportData?.actions).toHaveLength(1);
    expect(document.analysis?.strategy).toBe("simulation_informed");
    expect(openOptimizedGraph).not.toHaveBeenCalled();
  });
});
