import type { SimulationReportSummary } from "../../contracts.generated/dashboard/simulation";
import { expect, it } from "vitest";
import {
  formatCapabilityFlows,
  formatCapabilityStatusExplanation,
  formatCapabilitySupport,
  formatFeasibility,
  formatSimulationReportKpis,
} from "./simulation-report";

it("formats starting-scenario feasibility", () => {
  expect(formatFeasibility(true)).toBe("Operationally feasible");
  expect(formatFeasibility(false)).toBe("Not operationally feasible");
});

it("formats capability flow and support shortfalls", () => {
  expect(formatCapabilityFlows(3, 1)).toBe("2 / 3");
  expect(formatCapabilitySupport(1, 2)).toBe("1 / 2");
  expect(formatCapabilityStatusExplanation(3, 1, 1, 2)).toBe(
    "1 required flow unavailable; 1 supporting host required",
  );
  expect(formatCapabilityStatusExplanation(0, 0, 0, 0)).toBe(
    "No flow or support requirement",
  );
});

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
    expected_mission_impact: 6.5,
    median_mission_impact: 5,
    mission_impact_p95: 9.5,
    mission_impact_p99: 10,
    min_mission_impact: 1,
    max_mission_impact: 10,
    mission_impact_variance: 3,
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
    {
      label: "Expected mission impact",
      value: "6.5",
      detail: "Mean across 20 simulation runs",
      tone: "neutral",
    },
    {
      label: "Mission-impact 95th percentile",
      value: "9.5",
      detail: "99th percentile: 10",
      tone: "warning",
    },
  ]);
});
