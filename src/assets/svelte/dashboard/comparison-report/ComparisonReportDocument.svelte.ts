import type { IconName } from "../types";
import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import { WorkspaceDocumentBase } from "../workspace/WorkspaceDocument.svelte";

export class ComparisonReportDocument extends WorkspaceDocumentBase {
  readonly kind = "comparison-report" as const;
  readonly documentLabel = "Report";
  readonly icon = "simulation-report" as const satisfies IconName;
  readonly id = crypto.randomUUID();
  readonly title: string;
  readonly graphId: string;
  readonly graphRevisionId: string;
  hasUnread = $state(false);

  get analysisId(): string | undefined {
    return this.baselineReport.analysisId;
  }

  get analysisTitle(): string | undefined {
    return this.baselineReport.analysisTitle;
  }

  constructor(
    readonly baselineReport: SimulationReportDocument,
    readonly optimizationReport: OptimizationReportDocument,
    readonly postOptimizationReport: SimulationReportDocument,
  ) {
    super();
    this.graphId = baselineReport.graphId;
    this.graphRevisionId = baselineReport.graphRevisionId;
    this.title = `Comparison for ${baselineReport.title.replace(/^Report for /, "")}`;
  }

  isReportDocument(): true {
    return true;
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
