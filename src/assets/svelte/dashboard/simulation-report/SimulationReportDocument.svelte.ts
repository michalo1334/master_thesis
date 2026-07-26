import type { SimulationReportData } from "../contract";
import type { DashboardApi } from "../dashboard-api";

export class SimulationReportDocument {
  readonly kind = "simulation-report" as const;
  readonly id: string;
  readonly graphId: string;

  title = $state<string>("");
  status = $state<"pending" | "ready" | "loading" | "loaded" | "error">(
    "pending",
  );
  hasUnread = $state(false);
  experimentId = $state<string | null>(null);
  correlationId = $state<string | null>(null);
  reportData = $state<SimulationReportData | null>(null);
  errorReason = $state<string>("");

  constructor(graphTitle: string, graphId: string) {
    this.id = crypto.randomUUID();
    this.title = `Report for ${graphTitle}`;
    this.graphId = graphId;
  }

  markPending(correlationId: string): void {
    this.correlationId = correlationId;
    this.experimentId = null;
    this.status = "pending";
    this.reportData = null;
    this.errorReason = "";
  }

  markReady(experimentId: string): void {
    this.experimentId = experimentId;
    this.status = "ready";
    this.reportData = null;
    this.errorReason = "";
  }

  markError(reason: string): void {
    this.status = "error";
    this.errorReason = reason;
  }

  markRead(): void {
    this.hasUnread = false;
  }

  markUnread(): void {
    this.hasUnread = true;
  }

  setReportData(data: SimulationReportData): void {
    if (data.experiment_id !== this.experimentId) return;
    this.reportData = data;
    this.title = `Report for ${data.graph_title}`;
    this.status = "loaded";
  }

  complete(api: DashboardApi, experimentId: string, graphId: string): void {
    this.markReady(experimentId);
    this.load(api, experimentId, graphId);
  }

  load(api: DashboardApi, experimentId: string, graphId: string): void {
    this.experimentId = experimentId;
    this.status = "loading";
    this.errorReason = "";
    api.requestSimulationReport(experimentId, graphId);
  }
}
