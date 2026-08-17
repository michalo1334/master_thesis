import type { SimulationReportData } from "../contract";

export interface ComparisonMetric {
  label: string;
  baseline: number;
  postOptimization: number;
}

const formatNumber = (value: number) =>
  new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(value);

export function formatDelta(value: number): string {
  return `${value > 0 ? "+" : ""}${formatNumber(value)}`;
}

export function formatPercentDelta(
  baseline: number,
  postOptimization: number,
): string {
  if (baseline === 0) return "—";
  return `${postOptimization - baseline > 0 ? "+" : ""}${new Intl.NumberFormat(
    undefined,
    { style: "percent", maximumFractionDigits: 1 },
  ).format((postOptimization - baseline) / baseline)}`;
}

export function formatPercentagePointDelta(
  baseline: number,
  defended: number,
): string {
  return `${defended - baseline > 0 ? "+" : ""}${formatNumber(
    (defended - baseline) * 100,
  )} pp`;
}

export function comparisonMetrics(
  baseline: SimulationReportData,
  postOptimization: SimulationReportData,
): ComparisonMetric[] {
  const metrics: ComparisonMetric[] = [
    ["Expected blast radius", "expected_blast_radius"],
    ["Median blast radius", "median_blast_radius"],
    ["P95 blast radius", "blast_radius_p95"],
    ["P99 blast radius", "blast_radius_p99"],
  ].map(([label, key]) => ({
    label,
    baseline: baseline.summary[key as keyof typeof baseline.summary] as number,
    postOptimization: postOptimization.summary[
      key as keyof typeof postOptimization.summary
    ] as number,
  }));

  if (
    baseline.charts.capability_impact.length > 0 ||
    postOptimization.charts.capability_impact.length > 0
  ) {
    metrics.push(
      ...(
        [
          ["Expected mission impact", "expected_mission_impact"],
          ["Median mission impact", "median_mission_impact"],
          ["P95 mission impact", "mission_impact_p95"],
          ["P99 mission impact", "mission_impact_p99"],
        ] as const
      ).map(([label, key]) => ({
        label,
        baseline: baseline.summary[key],
        postOptimization: postOptimization.summary[key],
      })),
    );
  }

  return metrics;
}

export function formatStrategy(strategy: string): string {
  return (
    {
      cvss: "CVSS",
      simulation_informed: "Simulation-informed",
      topology_segmentation: "Topology segmentation",
      simulated_annealing: "Simulated annealing",
    }[strategy] ?? strategy
  );
}
