import type { SimulationReportSummary } from "../../contracts.generated";
import type { KpiMetric } from "./KpiCards.svelte";

const formatNumber = (value: number) =>
  new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(value);

export const formatProbability = (value: number) =>
  new Intl.NumberFormat(undefined, {
    style: "percent",
    maximumFractionDigits: 1,
  }).format(value);

export function formatSimulationReportKpis(
  summary: SimulationReportSummary,
  runCount: number,
): KpiMetric[] {
  return [
    {
      label: "Expected blast radius",
      value: `${formatNumber(summary.expected_blast_radius)} of ${formatNumber(summary.host_count)} hosts`,
      detail: `Mean across ${formatNumber(runCount)} simulation runs`,
      tone:
        summary.host_count > 0 &&
        summary.expected_blast_radius / summary.host_count > 0.5
          ? "warning"
          : "neutral",
    },
    {
      label: "Median blast radius",
      value: `${formatNumber(summary.median_blast_radius)} hosts`,
      detail: "Half of runs compromised no more hosts",
      tone: "neutral",
    },
    {
      label: "95th percentile",
      value: `${formatNumber(summary.blast_radius_p95)} hosts`,
      detail: `99th percentile: ${formatNumber(summary.blast_radius_p99)} hosts`,
      tone: "warning",
    },
    {
      label: "Spread",
      value: `${formatNumber(summary.min_blast_radius)}–${formatNumber(summary.max_blast_radius)} hosts`,
      detail: `Variance: ${formatNumber(summary.blast_radius_variance)}`,
      tone: "neutral",
    },
    {
      label: "Expected mission impact",
      value: formatNumber(summary.expected_mission_impact),
      detail: `Mean across ${formatNumber(runCount)} simulation runs`,
      tone: "neutral",
    },
    {
      label: "Mission-impact 95th percentile",
      value: formatNumber(summary.mission_impact_p95),
      detail: `99th percentile: ${formatNumber(summary.mission_impact_p99)}`,
      tone: "warning",
    },
  ];
}
