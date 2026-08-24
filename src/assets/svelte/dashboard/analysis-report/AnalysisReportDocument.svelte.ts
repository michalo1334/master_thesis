import type { EvaluationReport } from "../contract";
import type {
  EvaluationAnalysis,
  EvaluationAnalysisErrorEvent,
  EvaluationAnalysisReadyEvent,
  RequestEvaluationAnalysisPayload,
} from "../../contracts.generated";
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
  pilotAnalysis = $state<AnalysisSession>({
    status: "idle",
    data: null,
    error: "",
  });
  finalAnalysis = $state<AnalysisSession>({
    status: "idle",
    data: null,
    error: "",
  });

  reportData = $state<EvaluationReport | null>(null);
  openExperiment = $state<
    | ((experiment: {
        id: string;
        graph_id?: string | null;
        graph_revision_id?: string | null;
        graph_title?: string | null;
      }) => boolean)
    | undefined
  >();
  openOptimization = $state<
    | ((plan: {
        id: string;
        strategy?: string;
        requested_budget?: number;
      }) => boolean)
    | undefined
  >();
  openSourceGraph = $state<
    ((nodeId?: string) => boolean | Promise<boolean>) | undefined
  >();

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
    context.workspace.bindAnalysisReportNavigation(this, context.api);
    this.load(context.api, this.id, persisted.ids.runId);
  }

  markPending(): void {
    this.status = "pending";
    this.reportData = null;
    this.errorReason = "";
    this.progress = null;
    this.resetAnalysis();
  }

  markReady(): void {
    this.status = "ready";
    this.reportData = null;
    this.errorReason = "";
    this.progress = null;
    this.resetAnalysis();
  }

  setReportData(data: EvaluationReport): void {
    if (data.run_id !== this.runId) return;
    this.graphId = data.graph_id;
    this.graphRevisionId = data.source_graph_revision_id;
    this.title = `Analysis for ${data.manifest_title}`;
    if (data.status === "running") {
      this.reportData = null;
      this.status = "pending";
      return;
    }
    this.reportData = data;
    this.status = "loaded";
  }

  load(api: DashboardApi, documentId: string, runId: string): void {
    this.status = "loading";
    this.loadProgress = null;
    this.errorReason = "";
    api.requestEvaluationReport(documentId, runId);
  }

  async startAnalysis(
    api: DashboardApi,
    documentId: string,
    mode: RequestEvaluationAnalysisPayload["mode"],
  ): Promise<void> {
    const session = this.session(mode);
    if (session.status === "loading") return;
    session.status = "loading";
    session.data = null;
    session.error = "";
    const reply = await api.requestEvaluationAnalysis({
      document_id: documentId,
      run_id: this.runId,
      mode,
    });
    if (reply.status !== "processing") {
      session.status = "error";
      session.error = `Unable to start ${mode === "pilot" ? "pilot" : "final"} analysis (${reply.status}).`;
    }
  }

  setAnalysisReady(event: EvaluationAnalysisReadyEvent): void {
    if (!this.matchesAnalysisEvent(event)) return;
    const session = this.session(event.mode);
    session.status = "loaded";
    session.data = event.analysis;
    session.error = "";
  }

  setAnalysisError(event: EvaluationAnalysisErrorEvent): void {
    if (!this.matchesAnalysisEvent(event)) return;
    if (event.mode !== "pilot" && event.mode !== "analyze") return;
    const session = this.session(event.mode);
    session.status = "error";
    session.data = null;
    session.error = `Analysis failed (${event.error.code}).`;
  }

  private matchesAnalysisEvent(event: {
    document_id: string;
    run_id: string;
    mode: string;
  }): boolean {
    return (
      event.document_id === this.id &&
      event.run_id === this.runId &&
      (event.mode === "pilot" || event.mode === "analyze")
    );
  }

  private session(
    mode: RequestEvaluationAnalysisPayload["mode"],
  ): AnalysisSession {
    return mode === "pilot" ? this.pilotAnalysis : this.finalAnalysis;
  }

  private resetAnalysis(): void {
    this.pilotAnalysis = { status: "idle", data: null, error: "" };
    this.finalAnalysis = { status: "idle", data: null, error: "" };
  }
}

export type AnalysisSession = {
  status: "idle" | "loading" | "loaded" | "error";
  data: EvaluationAnalysis | null;
  error: string;
};

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
