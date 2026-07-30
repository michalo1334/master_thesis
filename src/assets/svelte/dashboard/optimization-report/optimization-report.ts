import type { KpiMetric } from "../simulation-report/KpiCards.svelte";
import type { OptimizationReport } from "../contract";
import { formatRuntime } from "../format";

const formatNumber = (value: number) =>
  new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(value);

export function formatOptimizationKpis(
  report: OptimizationReport,
): KpiMetric[] {
  return [
    {
      label: "Requested budget",
      value: formatNumber(report.requested_budget),
      detail: "Maximum defenses requested",
      tone: "neutral",
    },
    {
      label: "Used budget",
      value: formatNumber(report.used_budget),
      detail: "Cost of applied defenses",
      tone: "neutral",
    },
    {
      label: "Actions applied",
      value: formatNumber(report.actions.length),
      detail: "Defenses applied to the topology",
      tone: "positive",
    },
    {
      label: "Runtime",
      value: formatRuntime(report.runtime_ms),
      detail: "Optimization execution time",
      tone: "neutral",
    },
  ];
}
