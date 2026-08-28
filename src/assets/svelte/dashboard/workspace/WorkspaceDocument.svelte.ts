import type { DashboardError } from "../../contracts.generated/dashboard";
import type { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import type { DocumentCatalogDocument } from "../document-catalog/DocumentCatalogDocument.svelte";
import type { AnalysisReportDocument } from "../analysis-report/AnalysisReportDocument.svelte";
import type { RunsDocument } from "../runs/RunsDocument.svelte";
import type { ReportDataMap, ReportKind } from "../report-events";
import { formatDashboardErrorCode } from "../error-code";
import { UiWorkspaceDocument } from "../../ui-kit/workspace/WorkspaceDocument.svelte";

// ponytail: extends kit UiWorkspaceDocument - domain fields stay here per Option A.
// This concrete base stays app-side: it adds AsyncReportDocument + report accessors the kit does not have.
export abstract class WorkspaceDocumentBase extends UiWorkspaceDocument {
  isAsyncReportDocument(): this is AsyncReportDocument<ReportKind> {
    return false;
  }
}

export abstract class AsyncReportDocument<
  Kind extends ReportKind,
> extends WorkspaceDocumentBase {
  abstract readonly reportKind: Kind;
  abstract readonly runId: string | null;

  setRunId(_runId: string): void {
    // Reports that receive their run ID from the start reply override this.
  }

  isReportDocument(): true {
    return true;
  }

  isAsyncReportDocument(): this is AsyncReportDocument<Kind> {
    return true;
  }

  status = $state<
    "pending" | "ready" | "loading" | "loaded" | "error" | "cancelled"
  >("pending");
  progress = $state<{
    completed: number;
    total: number;
    detail?: string;
  } | null>(null);
  loadProgress = $state<{
    completed: number;
    total: number;
    detail?: string;
  } | null>(null);
  title = $state<string>("");
  hasUnread = $state(false);
  errorReason = $state<string>("");
  analysisId = $state<string>();
  analysisTitle = $state<string>();
  private cancelInProgressState = $state(false);

  get cancelInProgress(): boolean {
    return this.cancelInProgressState;
  }

  abstract get reportId(): string | null;

  abstract get reportApiKind():
    "simulation_report" | "optimization_report" | "evaluation_report";

  abstract setReportData(data: ReportDataMap[Kind]): void;

  needsRecovery(): boolean {
    return this.status === "ready" && this.persistedData !== undefined;
  }

  canClose(): boolean {
    return (
      this.status === "loaded" ||
      this.status === "error" ||
      this.status === "cancelled"
    );
  }

  markRead(): void {
    this.hasUnread = false;
  }

  markUnread(): void {
    this.hasUnread = true;
  }

  markError(error: DashboardError): void {
    this.markErrorMessage(formatDashboardErrorCode(error.code));
  }

  markErrorMessage(message: string): void {
    this.status = "error";
    this.errorReason = message;
  }

  markCancelled(): void {
    this.status = "cancelled";
    this.cancelInProgressState = false;
    this.progress = null;
    this.errorReason = "";
  }

  beginCancellation(): boolean {
    if (
      !this.runId ||
      this.cancelInProgressState ||
      this.status === "cancelled"
    )
      return false;
    this.cancelInProgressState = true;
    return true;
  }

  cancelFailed(): void {
    this.cancelInProgressState = false;
  }

  setProgress(completed: number, total: number, detail?: string): void {
    this.setProgressField("progress", "pending", completed, total, detail);
  }

  setLoadProgress(completed: number, total: number, detail?: string): void {
    this.setProgressField("loadProgress", "loading", completed, total, detail);
  }

  private setProgressField(
    field: "progress" | "loadProgress",
    guardStatus: "pending" | "loading",
    completed: number,
    total: number,
    detail?: string,
  ): void {
    if (this.status !== guardStatus) return;
    this[field] = { completed, total, ...(detail ? { detail } : {}) };
  }

  setAnalysis(analysis: { id: string; title: string } | null): void {
    this.analysisId = analysis?.id;
    this.analysisTitle = analysis?.title;
  }
}

export type WorkspaceDocument =
  | EditableGraphDocument
  | GraphDiffDocument
  | SimulationReportDocument
  | OptimizationReportDocument
  | AnalysisReportDocument
  | DocumentCatalogDocument
  | RunsDocument;

export function isReport(
  document: WorkspaceDocument,
): document is
  | SimulationReportDocument
  | OptimizationReportDocument
  | AnalysisReportDocument {
  return document.isReportDocument();
}

export function isGraphDiff(
  document: WorkspaceDocument,
): document is GraphDiffDocument {
  return document.kind === "graph-diff";
}
