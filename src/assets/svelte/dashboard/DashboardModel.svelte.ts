import { WorkspaceModel } from "./workspace/WorkspaceModel.svelte";
import { ManifestModel } from "./manifest/ManifestModel.svelte";
import { SvelteMap, SvelteSet } from "svelte/reactivity";
import type { DashboardApi } from "./dashboard-api";
import type {
  GraphSummary,
  FolderSummary,
  OptimizationCompletedEvent,
  OptimizationFailedEvent,
  ExecutionProgressEvent,
  SimulationCompletedEvent,
  SimulationFailedEvent,
} from "./contract";
import type { SimulationReportDocument } from "./simulation-report/SimulationReportDocument.svelte";
import type { OptimizationReportDocument } from "./optimization-report/OptimizationReportDocument.svelte";
import type { AnalysisReportDocument } from "./analysis-report/AnalysisReportDocument.svelte";
import type {
  ReportErrorEventType,
  ReportKind,
  ReportReadyEventType,
} from "./report-events";
import type { AsyncReportDocument } from "./workspace/WorkspaceDocument.svelte";
import type {
  EvaluationCompletedEvent,
  EvaluationFailedEvent,
  RunCancelledEvent,
} from "./contract";
import { formatDashboardErrorCode } from "./error-code";
import type { OptimizationParams, SimulationParams } from "./contract";
import type { EditableGraphDocument } from "./graph/EditableGraphDocument.svelte";
import type {
  EvaluationAnalysisReadyEvent,
  EvaluationAnalysisErrorEvent,
} from "../contracts.generated";

export class DashboardModel {
  workspace: WorkspaceModel;
  api: DashboardApi;
  manifest: ManifestModel;
  private pendingEvaluationEvents = new SvelteMap<
    string,
    EvaluationCompletedEvent | EvaluationFailedEvent
  >();
  // ponytail: last-only O(1) buffer — full history if UX needs scrubbing
  private pendingEvaluationProgressEvents = new SvelteMap<
    string,
    ExecutionProgressEvent
  >();
  private pendingCancellations = new SvelteSet<string>();

  private cancellationKey(kind: ReportKind, runId: string): string {
    return `${kind}:${runId}`;
  }

  private bindRunId(
    report: AsyncReportDocument<ReportKind>,
    runId: string,
  ): void {
    report.setRunId(runId);
    this.applyPendingCancellation(report);
  }

  private applyPendingCancellation(
    report: AsyncReportDocument<ReportKind>,
  ): void {
    const runId = report.runId;
    if (!runId) return;
    const key = this.cancellationKey(report.reportKind, runId);
    if (this.pendingCancellations.delete(key)) {
      report.markCancelled();
      this.workspace.markReportReadState(report);
    }
  }

  constructor(
    api: DashboardApi,
    graphSummaries: GraphSummary[] = [],
    folders: FolderSummary[] = [],
  ) {
    this.api = api;
    this.workspace = new WorkspaceModel(graphSummaries, folders, api);
    this.manifest = new ManifestModel(api);
    this.manifest.onStarted = (runId, manifest) => {
      const report = this.workspace.openPendingAnalysisReport(runId, manifest);
      this.applyPendingCancellation(report);
      if (report.status === "cancelled") return;
      const progress = this.pendingEvaluationProgressEvents.get(runId);
      if (progress) {
        this.pendingEvaluationProgressEvents.delete(runId);
        report.setProgress(
          progress.completed,
          progress.total,
          progress.detail ?? undefined,
        );
      }

      const event = this.pendingEvaluationEvents.get(runId);
      if (!event) return;

      this.pendingEvaluationEvents.delete(runId);
      if ("error" in event) this.onEvaluationFailed(event);
      else this.onEvaluationCompleted(event);
    };
  }

  /** Cross-model: start simulation on active graph, create pending report. */
  async runActiveSimulation(): Promise<void> {
    const doc = this.workspace.activeGraph;
    if (!doc) return;
    if (doc.isDirty && !(await doc.saveIfDirty(this.api))) {
      this.workspace.statusMessage = doc.saveStatusMessage;
      return;
    }
    await this.runSimulation(doc, this.workspace.simulationParams);
  }

  async runActiveOptimization(): Promise<void> {
    const doc = this.workspace.activeGraph;
    if (!doc || !doc.loadedRevisionId) {
      return;
    }
    if (doc.isDirty && !(await doc.saveIfDirty(this.api))) {
      this.workspace.statusMessage = doc.saveStatusMessage;
      return;
    }

    await this.runOptimization(
      doc,
      $state.snapshot(this.workspace.optimizationParams),
    );
  }

  private async runSimulation(
    document: EditableGraphDocument,
    params: SimulationParams,
  ): Promise<boolean> {
    const expectedJob = this.createJob(document);
    if (!expectedJob) return false;
    const report = this.workspace.createPendingReport({
      graphId: expectedJob.graphId,
      graphRevisionId: expectedJob.graphRevisionId,
      correlationId: expectedJob.correlationId,
      graphTitle: document.title,
    });

    try {
      const result = await document.startSimulation(
        this.api,
        params,
        expectedJob.correlationId,
      );
      if (!result) {
        report.markErrorMessage("Simulation failed.");
        this.workspace.markReportReadState(report);
        return false;
      }
      if (result.status === "rejected") {
        if (result.error) {
          report.markError(result.error);
        } else {
          report.markErrorMessage("Simulation rejected.");
        }
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = result.error
          ? `Simulation rejected: ${formatDashboardErrorCode(result.error.code)}`
          : "Simulation was rejected.";
        return false;
      }
      if (
        result.graphId !== expectedJob.graphId ||
        result.graphRevisionId !== expectedJob.graphRevisionId ||
        result.correlationId !== expectedJob.correlationId
      ) {
        report.markErrorMessage(
          "Simulation request returned unexpected identifiers.",
        );
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = report.errorReason;
        return false;
      }
      if (result.runId) this.bindRunId(report, result.runId);
      return true;
    } catch {
      report.markErrorMessage("Simulation failed.");
      this.workspace.markReportReadState(report);
      this.workspace.statusMessage = report.errorReason;
      return false;
    }
  }

  private async runOptimization(
    document: EditableGraphDocument,
    params: OptimizationParams,
  ): Promise<boolean> {
    const expectedJob = this.createJob(document);
    if (!expectedJob) return false;

    const report = this.workspace.createPendingOptimizationReport({
      graphId: expectedJob.graphId,
      graphRevisionId: expectedJob.graphRevisionId,
      graphTitle: document.title,
      correlationId: expectedJob.correlationId,
      strategy: params.strategy,
      budget: params.budget,
    });

    try {
      const reply = await document.startOptimization(
        this.api,
        params,
        expectedJob.correlationId,
      );
      if (!reply) {
        report.markErrorMessage("Optimization failed.");
        this.workspace.markReportReadState(report);
        return false;
      }
      if (reply.status === "rejected") {
        if (reply.error) {
          report.markError(reply.error);
        } else {
          report.markErrorMessage("Optimization rejected.");
        }
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = report.errorReason;
        return false;
      }
      if (
        reply.graph_revision_id !== expectedJob.graphRevisionId ||
        reply.correlation_id !== expectedJob.correlationId
      ) {
        report.markErrorMessage(
          "Optimization request returned unexpected identifiers.",
        );
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = report.errorReason;
        return false;
      }
      if (reply.run_id) this.bindRunId(report, reply.run_id);
      return true;
    } catch {
      report.markErrorMessage("Optimization failed.");
      this.workspace.markReportReadState(report);
      this.workspace.statusMessage = report.errorReason;
      return false;
    }
  }

  private createJob(
    document: EditableGraphDocument,
  ):
    | { graphId: string; graphRevisionId: string; correlationId: string }
    | undefined {
    const graphRevisionId = document.loadedRevisionId;
    if (!graphRevisionId) return undefined;

    return {
      graphId: document.graph.id,
      graphRevisionId,
      correlationId: crypto.randomUUID(),
    };
  }

  onOptimizationCompleted(payload: OptimizationCompletedEvent): void {
    const report = this.workspace.findOptimizationReport(
      payload.correlation_id,
      payload.graph_id,
    );
    if (report) {
      if (report.status === "cancelled") return;
      report.complete(
        this.api,
        payload,
        () =>
          this.workspace.openOptimizationResult(
            this.api,
            payload.output_graph_revision_id,
          ),
        () =>
          this.workspace.loadOptimizationGraphDiff(
            this.api,
            report.graphRevisionId,
            payload.output_graph_revision_id,
          ),
      );
      this.workspace.markReportReadState(report);
    }
  }

  onOptimizationFailed(payload: OptimizationFailedEvent): void {
    const report = this.workspace.findOptimizationReport(
      payload.correlation_id,
      payload.graph_id,
    );
    if (report) {
      if (report.status === "cancelled") return;
      report.markError(payload.error);
      this.workspace.markReportReadState(report);
    }
  }

  onProgress(
    kind: "simulation" | "optimization" | "evaluation",
    payload: ExecutionProgressEvent,
  ): void {
    if (kind === "simulation") this.onSimulationProgress(payload);
    else if (kind === "optimization") this.onOptimizationProgress(payload);
    else this.onEvaluationProgress(payload);
  }

  onSimulationProgress(payload: ExecutionProgressEvent): void {
    const report = this.findSimulationReport(
      payload.correlation_id,
      payload.graph_revision_id,
    );
    report?.setProgress(
      payload.completed,
      payload.total,
      payload.detail ?? undefined,
    );
  }

  onOptimizationProgress(payload: ExecutionProgressEvent): void {
    const report = this.workspace.findOptimizationReport(
      payload.correlation_id,
      payload.graph_id,
    );
    report?.setProgress(
      payload.completed,
      payload.total,
      payload.detail ?? undefined,
    );
  }

  onEvaluationProgress(payload: ExecutionProgressEvent): void {
    const report = this.findAnalysisReport(payload.correlation_id);
    if (!report) {
      this.pendingEvaluationProgressEvents.set(payload.correlation_id, payload);
      return;
    }

    this.pendingEvaluationProgressEvents.delete(payload.correlation_id);
    report.setProgress(
      payload.completed,
      payload.total,
      payload.detail ?? undefined,
    );
  }

  onReportProgress(
    kind: "simulation" | "optimization" | "evaluation",
    payload: ExecutionProgressEvent,
  ): void {
    const report = this.workspace.documents.find(
      (document) =>
        document.isAsyncReportDocument() &&
        document.reportKind === kind &&
        document.reportId === payload.correlation_id,
    );
    if (!report?.isAsyncReportDocument()) return;
    report.setLoadProgress(
      payload.completed,
      payload.total,
      payload.detail ?? undefined,
    );
  }

  /** Cross-model: route a server completion event to the matching report. */
  onSimulationCompleted(payload: SimulationCompletedEvent): void {
    const report = this.findSimulationReport(
      payload.correlation_id,
      payload.graph_revision_id,
    );
    if (report) {
      if (report.status === "cancelled") return;
      report.complete(this.api, payload.experiment_id);
      this.workspace.markReportReadState(report);
    }
  }

  /** Cross-model: route a server failure event to the matching report. */
  onSimulationFailed(payload: SimulationFailedEvent): void {
    const report = this.findSimulationReport(
      payload.correlation_id,
      payload.graph_revision_id,
    );
    if (report) {
      if (report.status === "cancelled") return;
      report.markError(payload.error);
      this.workspace.markReportReadState(report);
    }
  }

  private findReport<Kind extends ReportKind>(
    documentId: string,
    reportKind: Kind,
  ):
    | (AsyncReportDocument<Kind> & {
        readonly id: string;
        markRead(): void;
        markUnread(): void;
      })
    | undefined {
    const document = this.workspace.documents.find(
      (candidate) =>
        candidate.isAsyncReportDocument() &&
        candidate.id === documentId &&
        candidate.reportKind === reportKind,
    );
    return document as
      | (AsyncReportDocument<Kind> & {
          readonly id: string;
          markRead(): void;
          markUnread(): void;
        })
      | undefined;
  }

  onReportReadyEvent<Kind extends ReportKind>(
    event: ReportReadyEventType<Kind>,
  ): void {
    const document = this.findReport(
      event.payload.document_id,
      event.reportKind,
    );
    if (document?.status === "cancelled") return;
    document?.setReportData(event.payload.report);
  }

  onReportErrorEvent<Kind extends ReportKind>(
    event: ReportErrorEventType<Kind>,
  ): void {
    const document = this.findReport(
      event.payload.document_id,
      event.reportKind,
    );
    if (!document) return;
    if (document.status === "cancelled") return;
    document.markError(event.payload.error);
    this.workspace.markReportReadState(document);
  }

  onEvaluationCompleted(payload: EvaluationCompletedEvent): void {
    this.announceEvaluationReport(payload);
  }

  onEvaluationFailed(payload: EvaluationFailedEvent): void {
    this.announceEvaluationReport(payload);
  }

  onRunCancelled(payload: RunCancelledEvent): void {
    const kind = payload.kind as ReportKind;
    const report = this.workspace.documents.find(
      (document) =>
        document.isAsyncReportDocument() &&
        document.reportKind === kind &&
        document.runId === payload.run_id,
    );
    if (report?.isAsyncReportDocument()) {
      report.markCancelled();
      this.workspace.markReportReadState(report);
    } else {
      this.pendingCancellations.add(this.cancellationKey(kind, payload.run_id));
    }
  }

  async cancelReport(
    report: AsyncReportDocument<ReportKind>,
  ): Promise<boolean> {
    const runId = report.runId;
    if (!runId) return false;
    if (!globalThis.confirm("Cancel this run?")) return false;
    if (!report.beginCancellation()) return false;
    try {
      const reply = await this.api.cancelRun({
        kind: report.reportKind,
        run_id: runId,
      });
      if (reply.status === "cancelled") {
        this.onRunCancelled({ kind: report.reportKind, run_id: runId });
        return true;
      }
    } catch {
      // The report remains cancellable after a transport failure.
    }
    report.cancelFailed();
    return false;
  }

  onEvaluationAnalysisReady(payload: EvaluationAnalysisReadyEvent): void {
    const report = this.findReport(payload.document_id, "evaluation") as
      AnalysisReportDocument | undefined;
    if (report?.status === "cancelled") return;
    report?.setAnalysisReady(payload);
  }

  onEvaluationAnalysisError(payload: EvaluationAnalysisErrorEvent): void {
    const report = this.findReport(payload.document_id, "evaluation") as
      AnalysisReportDocument | undefined;
    if (report?.status === "cancelled") return;
    report?.setAnalysisError(payload);
  }

  private announceEvaluationReport(
    payload: EvaluationCompletedEvent | EvaluationFailedEvent,
  ): void {
    const report = this.findAnalysisReport(payload.run_id);
    if (!report) {
      this.pendingEvaluationEvents.set(payload.run_id, payload);
      return;
    }
    if (report.status === "cancelled") return;
    // Already loaded: the server re-announces terminal runs; don't refetch.
    if (report.status === "loaded") {
      this.workspace.markReportReadState(report);
      return;
    }
    report.markReady();
    report.load(this.api, report.id, payload.run_id);
    this.workspace.markReportReadState(report);
  }

  private findSimulationReport(
    correlationId: string,
    graphRevisionId: string,
  ): SimulationReportDocument | undefined {
    return this.workspace.documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        d.correlationId === correlationId &&
        d.graphRevisionId === graphRevisionId,
    ) as SimulationReportDocument | undefined;
  }

  private findAnalysisReport(
    runId: string,
  ): AnalysisReportDocument | undefined {
    return this.workspace.documents.find(
      (d) => d.kind === "analysis-report" && d.runId === runId,
    ) as AnalysisReportDocument | undefined;
  }

  /** Delegate saving to the workspace. */
  async saveActiveGraph(): Promise<boolean> {
    return this.workspace.saveActiveGraph(this.api);
  }

  /** Delegate force layout to the workspace. */
  applyForceLayout(): void {
    this.workspace.applyForceLayout();
  }
}
