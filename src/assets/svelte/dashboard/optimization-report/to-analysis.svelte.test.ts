import type { OptimizationReport } from "../../contracts.generated/dashboard/optimization";
import { describe, expect, it } from "vitest";
import { formatOptimizationKpis } from "./optimization-report";
import { toOptimizationAnalysis } from "./to-analysis";

const report: OptimizationReport = {
  strategy: "topology_segmentation",
  requested_budget: 3,
  used_budget: 2,
  runtime_ms: 1250,
  actions: [
    {
      id: "block-1",
      label: "Cut source-segment to target-segment (tcp:443-443)",
      kind: "Segment-boundary cut",
      cost: 2,
    },
  ],
};

describe("optimization report presentation", () => {
  it("maps a generated report to shared analysis", () => {
    expect(toOptimizationAnalysis(report)).toMatchObject({
      strategy: "topology_segmentation",
      actions: [{ id: "block-1" }],
    });
  });

  it("uses the generic analysis fallback for unknown strategies", () => {
    expect(
      toOptimizationAnalysis({
        ...report,
        strategy: "future_strategy",
      } as unknown as OptimizationReport),
    ).toMatchObject({ strategy: "unknown", actions: [{ id: "block-1" }] });
  });

  it("formats generated report overview metrics", () => {
    expect(formatOptimizationKpis(report).map(({ label }) => label)).toEqual([
      "Requested budget",
      "Used budget",
      "Actions applied",
      "Runtime",
    ]);
  });
});
