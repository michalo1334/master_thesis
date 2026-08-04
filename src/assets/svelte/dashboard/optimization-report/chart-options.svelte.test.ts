import { describe, expect, it } from "vitest";
import { cvssOptions } from "./chart-options";

describe("cvssOptions", () => {
  it("creates a horizontal chart from actions with CVSS scores only", () => {
    expect(
      cvssOptions([
        {
          id: "patch-1",
          label: "Patch CVE-1",
          kind: "patch_vulnerability",
          cost: 1,
          cvss_score: 9.8,
        },
        {
          id: "block-1",
          label: "Cut source-segment to target-segment (tcp:443-443)",
          kind: "Segment-boundary cut",
          cost: 2,
        },
      ]),
    ).toMatchObject({
      xAxis: { type: "value", min: 0, max: 10 },
      yAxis: { type: "category", data: ["Patch CVE-1"] },
      series: [{ type: "bar", data: [9.8] }],
    });
  });
});
