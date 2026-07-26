import { expect, it } from "vitest";
import type { SimulationReportSummary } from "../../contracts.generated";
import { formatSimulationReportKpis } from "./simulation-report";

it("formats simulation summary KPIs with their intended tones", () => {
  const summary: SimulationReportSummary = {
    expected_blast_radius: 6,
    host_count: 10,
    median_blast_radius: 5,
    blast_radius_p95: 9,
    blast_radius_p99: 10,
    min_blast_radius: 1,
    max_blast_radius: 10,
    blast_radius_variance: 3,
  };

  expect(formatSimulationReportKpis(summary, 20)).toEqual([
    {
      label: "Expected blast radius",
      value: "6 of 10 hosts",
      detail: "Mean across 20 simulation runs",
      tone: "warning",
    },
    {
      label: "Median blast radius",
      value: "5 hosts",
      detail: "Half of runs compromised no more hosts",
      tone: "neutral",
    },
    {
      label: "95th percentile",
      value: "9 hosts",
      detail: "99th percentile: 10 hosts",
      tone: "warning",
    },
    {
      label: "Spread",
      value: "1–10 hosts",
      detail: "Variance: 3",
      tone: "neutral",
    },
  ]);
});
