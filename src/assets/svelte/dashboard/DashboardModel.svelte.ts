import { WorkspaceModel } from "./workspace/WorkspaceModel.svelte";
import type { DashboardApi } from "./dashboard-api";
import type {
  GraphSummary,
  OptimizationCompletedEvent,
  OptimizationFailedEvent,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  SimulationProgressEvent,
  ExperimentSummary,
  FetchSimulationReportReply,
} from "./contract";
import type { SimulationReportErrorEvent } from "./contract";
import type { SimulationReportDocument } from "./simulation-report/SimulationReportDocument.svelte";

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
    if (!doc || this.workspace.isOptimizationPending || !doc.loadedGraphId) {
      return;
    }

    const correlationId = crypto.randomUUID();
    if (
      !this.workspace.beginOptimization({
        graphId: doc.loadedGraphId,
        correlationId,
      })
    ) {
      return;
    }

    const params = this.workspace.optimizationParams;
    try {
      const reply = await doc.startOptimization(
        this.api,
        {
          ...params,
          simulation_params: { ...this.workspace.simulationParams },
        },
        correlationId,
      );
      if (!reply) {
        this.workspace.cancelOptimization(correlationId);
      } else if (reply.status === "accepted") {
        this.workspace.confirmOptimization({
          graphId: reply.graph_id,
          correlationId: reply.correlation_id,
        });
      } else {
        this.workspace.cancelOptimization(correlationId);
        this.workspace.statusMessage = reply.reason || "Optimization rejected.";
      }
    } catch {
      this.workspace.cancelOptimization(correlationId);
      this.workspace.statusMessage = "Optimization failed.";
    }
  }

  async onOptimizationCompleted(
    payload: OptimizationCompletedEvent,
  ): Promise<void> {
    if (
      !this.workspace.finishOptimization(
        payload.correlation_id,
        payload.graph_id,
      )
    ) {
      return;
    }
    await this.workspace.openOptimizationResult(
      this.api,
      payload.optimized_graph_id,
    );
  }

  onOptimizationFailed(payload: OptimizationFailedEvent): void {
    if (
      this.workspace.finishOptimization(
        payload.correlation_id,
        payload.graph_id,
      )
    ) {
      this.workspace.statusMessage = payload.reason;
    }
  }

  /** Cross-model: route a server completion event to the matching report. */
  onSimulationCompleted(payload: SimulationCompletedEvent): void {
    const report = this.workspace.documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        d.correlationId === payload.correlation_id &&
        d.graphId === payload.graph_id,
    ) as SimulationReportDocument | undefined;
    if (!report) return;
    report.complete(this.api, payload.experiment_id, payload.graph_id);
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
        d.graphId === payload.graph_id,
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
        d.graphId === payload.graph_id,
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
  async saveActiveGraph(): Promise<void> {
    await this.workspace.saveActiveGraph(this.api);
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
}
