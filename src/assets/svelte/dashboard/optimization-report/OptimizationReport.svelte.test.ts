import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import OptimizationReportComponent from "./OptimizationReport.svelte";
import { OptimizationReportDocument } from "./OptimizationReportDocument.svelte";
import type { OptimizationReport } from "../contract";

afterEach(cleanup);

describe("OptimizationReport", () => {
  it("separates the overview, defense plan, and unknown strategy fallback", async () => {
    const openOptimizedGraph = vi.fn().mockResolvedValue(true);
    const document = new OptimizationReportDocument({
      graphId: "g1",
      graphTitle: "Topology",
      correlationId: "corr-1",
      strategy: "cvss",
      budget: 2,
    });
    document.complete(
      {
        correlation_id: "corr-1",
        graph_id: "g1",
        optimized_graph_id: "optimized-g1",
        report: {
          strategy: "future_strategy",
          requested_budget: 2,
          used_budget: 1,
          runtime_ms: 25,
          actions: [
            {
              id: "patch-1",
              label: "Patch CVE-1",
              kind: "patch_vulnerability",
              cost: 1,
              cvss_score: 9.8,
            },
          ],
        } as unknown as OptimizationReport,
      },
      openOptimizedGraph,
    );

    render(OptimizationReportComponent, { props: { document } });

    await fireEvent.click(
      screen.getByRole("button", { name: "Open optimized graph" }),
    );
    expect(openOptimizedGraph).toHaveBeenCalledOnce();

    await fireEvent.click(screen.getByRole("tab", { name: "Defense plan" }));
    expect(
      screen.getByRole("columnheader", { name: "Action" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("columnheader", { name: "CVSS" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Patch CVE-1")).toBeInTheDocument();

    await fireEvent.click(
      screen.getByRole("tab", { name: "Strategy analysis" }),
    );
    expect(
      screen.getByRole("heading", { name: "Strategy analysis unavailable" }),
    ).toBeInTheDocument();
  });
});
