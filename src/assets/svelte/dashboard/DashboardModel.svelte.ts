import { WorkspaceModel } from "./workspace/WorkspaceModel.svelte";
import type { DashboardApi } from "./dashboard-api";
import type {
  GraphSummary,
  OptimizationCompletedEvent,
  OptimizationFailedEvent,
  OptimizationProgressEvent,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  SimulationProgressEvent,
  ExperimentSummary,
  FetchSimulationReportReply,
  SimulationReportErrorEvent,
} from "./contract";
import type { SimulationReportDocument } from "./simulation-report/SimulationReportDocument.svelte";
import type { OptimizationReportDocument } from "./optimization-report/OptimizationReportDocument.svelte";

export class DashboardModel {
  workspace: WorkspaceModel;
  api: DashboardApi;

  constructor(api: DashboardApi, graphSummaries: GraphSummary[] = []) {
    this.api = api;
    this.workspace = new WorkspaceModel(graphSummaries);
  }

  /** Cross-model: start simulation on active graph, create pending report. */
  async runActiveSimulation(): Promise<void> {
    const doc = this.workspace.activeGraph;
    if (!doc) return;
    if (doc.isDirty && !(await doc.saveIfDirty(this.api))) {
      this.workspace.statusMessage = doc.saveStatusMessage;
      return;
    }
    const result = await doc.startSimulation(
      this.api,
      this.workspace.simulationParams,
    );
    if (result) {
      this.workspace.createPendingReport(result);
    }
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

    const params = $state.snapshot(this.workspace.optimizationParams);
    const correlationId = crypto.randomUUID();
    const report = this.workspace.createPendingOptimizationReport({
      graphId: doc.graph.id,
      graphRevisionId: doc.loadedRevisionId,
      graphTitle: doc.title,
      correlationId,
      strategy: params.strategy,
      budget: params.budget,
    });

    try {
      const reply = await doc.startOptimization(
        this.api,
        params,
        correlationId,
      );
      if (!reply) {
        report.markError("Optimization failed.");
        this.markOptimizationReportReadState(report);
      } else if (reply.status === "rejected") {
        report.markError(reply.reason || "Optimization rejected.");
        this.markOptimizationReportReadState(report);
        this.workspace.statusMessage = report.errorReason;
      }
    } catch {
      report.markError("Optimization failed.");
      this.markOptimizationReportReadState(report);
      this.workspace.statusMessage = report.errorReason;
    }
  }

  onOptimizationCompleted(payload: OptimizationCompletedEvent): void {
    const report = this.workspace.findOptimizationReport(
      payload.correlation_id,
      payload.graph_id,
    );
    if (!report) return;
    report.complete(
      payload,
      () =>
        this.workspace.openOptimizationResult(
          this.api,
          payload.graph_revision_id,
        ),
      () =>
        this.workspace.loadOptimizationGraphDiff(
          this.api,
          report.graphRevisionId,
          payload.graph_revision_id,
        ),
    );
    this.markOptimizationReportReadState(report);
  }

  onOptimizationFailed(payload: OptimizationFailedEvent): void {
    const report = this.workspace.findOptimizationReport(
      payload.correlation_id,
      payload.graph_id,
    );
    if (!report) return;
    report.markError(payload.reason);
    this.markOptimizationReportReadState(report);
  }

  onOptimizationProgress(payload: OptimizationProgressEvent): void {
    const report = this.workspace.findOptimizationReport(
      payload.correlation_id,
      payload.graph_id,
    );
    report?.setProgress(
      payload.completed_steps,
      payload.total_steps,
      payload.phase,
    );
  }

  /** Cross-model: route a server completion event to the matching report. */
  onSimulationCompleted(payload: SimulationCompletedEvent): void {
    const report = this.workspace.documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        d.correlationId === payload.correlation_id &&
        d.graphRevisionId === payload.graph_revision_id,
    ) as SimulationReportDocument | undefined;
    if (!report) return;
    report.complete(this.api, payload.experiment_id, payload.graph_revision_id);
    if (this.workspace.selectedDocumentId === report.id) {
      report.markRead();
    } else {
      report.markUnread();
    }
  }

  /** Cross-model: route a server failure event to the matching report. */
  onSimulationFailed(payload: SimulationFailedEvent): void {
    const report = this.workspace.documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        d.correlationId === payload.correlation_id &&
        d.graphRevisionId === payload.graph_revision_id,
    ) as SimulationReportDocument | undefined;
    if (!report) return;
    report.markError(payload.reason);
    if (this.workspace.selectedDocumentId === report.id) {
      report.markRead();
    } else {
      report.markUnread();
    }
  }

  onSimulationProgress(payload: SimulationProgressEvent): void {
    const report = this.workspace.documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        d.correlationId === payload.correlation_id &&
        d.graphRevisionId === payload.graph_revision_id,
    ) as SimulationReportDocument | undefined;
    if (!report) return;
    report.setProgress(payload.completed_runs, payload.total_runs);
  }

  onSimulationReportReady(payload: FetchSimulationReportReply): void {
    const report = this.workspace.documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        d.experimentId === payload.experiment_id,
    ) as SimulationReportDocument | undefined;
    if (!report) return;
    report.setReportData(payload);
  }

  onSimulationReportError(payload: SimulationReportErrorEvent): void {
    const report = this.workspace.documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        d.experimentId === payload.experiment_id,
    ) as SimulationReportDocument | undefined;
    if (!report) return;
    report.markError(payload.reason);
  }

  /** Delegate saving to the workspace. */
  async saveActiveGraph(): Promise<boolean> {
    return this.workspace.saveActiveGraph(this.api);
  }

  /** Delegate force layout to the workspace. */
  applyForceLayout(): void {
    this.workspace.applyForceLayout();
  }

  /** Delegate historical report picker opening to the workspace. */
  async showExperiments(): Promise<void> {
    await this.workspace.showExperiments(this.api);
  }

  /** Delegate historical report selection to the workspace. */
  async selectExperiment(experiment: ExperimentSummary): Promise<boolean> {
    return this.workspace.selectExperiment(this.api, experiment);
  }

  private markOptimizationReportReadState(
    report: OptimizationReportDocument,
  ): void {
    if (this.workspace.selectedDocumentId === report.id) {
      report.markRead();
    } else {
      report.markUnread();
    }
  }
}
