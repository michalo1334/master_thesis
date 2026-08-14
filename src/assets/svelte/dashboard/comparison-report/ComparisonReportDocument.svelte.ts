import type { IconName } from "../types";
import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";

export class ComparisonReportDocument {
  readonly kind = "comparison-report" as const;
  readonly icon = "simulation-report" as const satisfies IconName;
  readonly id = crypto.randomUUID();
  readonly title: string;
  readonly graphId: string;
  readonly graphRevisionId: string;
  hasUnread = $state(false);

  constructor(
    readonly baselineReport: SimulationReportDocument,
    readonly optimizationReport: OptimizationReportDocument,
    readonly postOptimizationReport: SimulationReportDocument,
  ) {
    this.graphId = baselineReport.graphId;
    this.graphRevisionId = baselineReport.graphRevisionId;
    this.title = `Comparison for ${baselineReport.title.replace(/^Report for /, "")}`;
  }

  loadGraphDiff(): Promise<boolean> {
    return this.optimizationReport.loadGraphDiff();
  }

  markRead(): void {
    this.hasUnread = false;
  }

  markUnread(): void {
    this.hasUnread = true;
  }
}
