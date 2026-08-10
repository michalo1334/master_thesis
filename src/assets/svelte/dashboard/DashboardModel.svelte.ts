import { WorkspaceModel } from "./workspace/WorkspaceModel.svelte";
import { AnalysisModel } from "./analysis/AnalysisModel.svelte";
import type { DashboardApi } from "./dashboard-api";
import type {
  GraphSummary,
  FolderSummary,
  OptimizationCompletedEvent,
  OptimizationFailedEvent,
  OptimizationProgressEvent,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  SimulationProgressEvent,
  FetchSimulationReportReply,
  SimulationReportErrorEvent,
  FetchOptimizationReportReply,
  OptimizationReportErrorEvent,
} from "./contract";
import type { SimulationReportDocument } from "./simulation-report/SimulationReportDocument.svelte";
import type { OptimizationReportDocument } from "./optimization-report/OptimizationReportDocument.svelte";

export class DashboardModel {
  workspace: WorkspaceModel;
  api: DashboardApi;
  analysis: AnalysisModel;

  constructor(
    api: DashboardApi,
    graphSummaries: GraphSummary[] = [],
    folders: FolderSummary[] = [],
  ) {
    this.api = api;
    this.workspace = new WorkspaceModel(graphSummaries, folders);
    this.analysis = new AnalysisModel(api, this.workspace);
  }

  /** Cross-model: start simulation on active graph, create pending report. */
  async runActiveSimulation(): Promise<void> {
    if (this.analysis.sequence.active) {
      this.workspace.statusMessage = "Compound analysis is in progress.";
      return;
    }
    const doc = this.workspace.activeGraph;
    if (!doc) return;
    if (doc.isDirty && !(await doc.saveIfDirty(this.api))) {
      this.workspace.statusMessage = doc.saveStatusMessage;
      return;
    }
    await this.analysis.runSimulation(doc, this.workspace.simulationParams);
  }

  async runActiveOptimization(): Promise<void> {
    if (this.analysis.sequence.active) {
      this.workspace.statusMessage = "Compound analysis is in progress.";
      return;
    }
    const doc = this.workspace.activeGraph;
    if (!doc || !doc.loadedRevisionId) {
      return;
    }
    if (doc.isDirty && !(await doc.saveIfDirty(this.api))) {
      this.workspace.statusMessage = doc.saveStatusMessage;
      return;
    }

    await this.analysis.runOptimization(
      doc,
      $state.snapshot(this.workspace.optimizationParams),
    );
  }

  onOptimizationCompleted(payload: OptimizationCompletedEvent): void {
    const report = this.workspace.findOptimizationReport(
      payload.correlation_id,
      payload.graph_id,
    );
    if (report) {
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
    this.analysis.onOptimizationCompleted(payload);
  }

  onOptimizationFailed(payload: OptimizationFailedEvent): void {
    const report = this.workspace.findOptimizationReport(
      payload.correlation_id,
      payload.graph_id,
    );
    if (report) {
      report.markError(payload.reason);
      this.workspace.markReportReadState(report);
    }
    this.analysis.onOptimizationFailed(payload);
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
    if (report) {
      report.complete(
        this.api,
        payload.experiment_id,
        payload.graph_revision_id,
      );
      this.workspace.markReportReadState(report);
    }
    this.analysis.onSimulationCompleted(payload);
  }

  /** Cross-model: route a server failure event to the matching report. */
  onSimulationFailed(payload: SimulationFailedEvent): void {
    const report = this.workspace.documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        d.correlationId === payload.correlation_id &&
        d.graphRevisionId === payload.graph_revision_id,
    ) as SimulationReportDocument | undefined;
    if (report) {
      report.markError(payload.reason);
      this.workspace.markReportReadState(report);
    }
    this.analysis.onSimulationFailed(payload);
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

  onOptimizationReportReady(payload: FetchOptimizationReportReply): void {
    const report = this.workspace.documents.find(
      (d) =>
        d.kind === "optimization-report" &&
        d.optimizationId === payload.optimization_id,
    ) as OptimizationReportDocument | undefined;
    report?.setReportData(payload);
  }

  onOptimizationReportError(payload: OptimizationReportErrorEvent): void {
    const report = this.workspace.documents.find(
      (d) =>
        d.kind === "optimization-report" &&
        d.optimizationId === payload.optimization_id,
    ) as OptimizationReportDocument | undefined;
    report?.markError(payload.reason);
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
