import type {
  OptimizationAction,
  OptimizationReport,
} from "../../contracts.generated/dashboard/optimization";

export interface OptimizationPresentation {
  report: OptimizationReport;
  actions: readonly OptimizationAction[];
  strategy: OptimizationReport["strategy"] | "unknown";
}

export function toOptimizationPresentation(
  report: OptimizationReport,
): OptimizationPresentation {
  const base = { report, actions: report.actions };
  switch (report.strategy) {
    case "cvss":
    case "simulation_informed":
    case "topology_segmentation":
    case "simulated_annealing":
      return { ...base, strategy: report.strategy };
    default:
      return { ...base, strategy: "unknown" };
  }
}
