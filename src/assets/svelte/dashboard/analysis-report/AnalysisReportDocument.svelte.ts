import type { EvaluationReport } from "../contract";
import type { DashboardApi } from "../dashboard-api";
import { AsyncReportDocument } from "../workspace/WorkspaceDocument.svelte";
import type { DashboardRecoveryContext } from "../workspace/recovery-context";
import {
  isPersistedDocumentOfKind,
  type PersistedWorkspaceDocument,
} from "../../ui-kit/workspace/workspace-persistence";

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

  reportData = $state<EvaluationReport | null>(null);

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

  static fromPersisted(
    data: unknown,
    _context: DashboardRecoveryContext,
  ): AnalysisReportDocument | undefined {
    if (!isAnalysisReportPersisted(data)) return undefined;
    const report = new AnalysisReportDocument(data.ids.runId, {
      manifest_id: data.ids.manifestId,
      title: "",
    });
    report.title = data.title;
    report.markReady();
    report.setPersisted(data);
    return report;
  }

  toPersisted(): PersistedWorkspaceDocument | undefined {
    return {
      kind: "analysis-report",
      ids: { runId: this.runId, manifestId: this.manifestId },
      title: this.title,
    };
  }

  recover(context: DashboardRecoveryContext): void {
    const persisted = this.persistedData as PersistedAnalysisReport | undefined;
    if (!persisted) return;
    this.load(context.api, this.id, persisted.ids.runId);
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

  load(api: DashboardApi, documentId: string, runId: string): void {
    this.status = "loading";
    this.loadProgress = null;
    this.errorReason = "";
    api.requestEvaluationReport(documentId, runId);
  }
}

type PersistedAnalysisReport = PersistedWorkspaceDocument & {
  ids: { runId: string; manifestId: string };
};

function isAnalysisReportPersisted(
  value: unknown,
): value is PersistedAnalysisReport {
  return isPersistedDocumentOfKind<PersistedAnalysisReport["ids"]>(
    value,
    "analysis-report",
    ["runId", "manifestId"],
  );
}
