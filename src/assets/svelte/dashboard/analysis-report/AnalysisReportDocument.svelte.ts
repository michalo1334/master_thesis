import type { DashboardError, EvaluationReport } from "../contract";
import type { DashboardApi } from "../dashboard-api";
import { formatDashboardErrorCode } from "../error-code";
import { AsyncReportDocument } from "../workspace/WorkspaceDocument.svelte";

export class AnalysisReportDocument extends AsyncReportDocument<"evaluation"> {
  readonly kind = "analysis-report" as const;
  readonly documentLabel = "Report";
  readonly reportKind = "evaluation" as const;
  readonly icon = "simulation-report" as const satisfies string;
  readonly id: string;
  readonly runId: string;
  readonly manifestId: string;
  readonly manifestTitle: string;
  graphId = $state("");
  graphRevisionId = $state("");

  title = $state<string>("");
  hasUnread = $state(false);
  reportData = $state<EvaluationReport | null>(null);
  errorReason = $state<string>("");

  get reportId(): string | null {
    return this.runId;
  }

  get reportApiKind():
    "simulation_report" | "optimization_report" | "evaluation_report" {
    return "evaluation_report";
  }

  constructor(runId: string, manifest: { manifest_id: string; title: string }) {
    super();
    this.id = crypto.randomUUID();
    this.runId = runId;
    this.manifestId = manifest.manifest_id;
    this.manifestTitle = manifest.title;
    this.title = `Analysis for ${manifest.title}`;
  }

  markPending(): void {
    this.status = "pending";
    this.reportData = null;
    this.errorReason = "";
    this.progress = null;
  }

  markReady(): void {
    this.status = "ready";
    this.reportData = null;
    this.errorReason = "";
    this.progress = null;
  }

  setReportData(data: EvaluationReport): void {
    if (data.run_id !== this.runId) return;
    this.reportData = data;
    this.graphId = data.graph_id;
    this.graphRevisionId = data.source_graph_revision_id;
    this.title = `Analysis for ${data.manifest_title}`;
    this.status = "loaded";
  }

  markError(error: DashboardError): void {
    this.status = "error";
    this.errorReason = formatDashboardErrorCode(error.code);
  }

  canClose(): boolean {
    return this.status === "loaded" || this.status === "error";
  }

  markRead(): void {
    this.hasUnread = false;
  }

  markUnread(): void {
    this.hasUnread = true;
  }

  load(api: DashboardApi, documentId: string, runId: string): void {
    this.status = "loading";
    this.errorReason = "";
    api.requestEvaluationReport(documentId, runId);
  }
}
