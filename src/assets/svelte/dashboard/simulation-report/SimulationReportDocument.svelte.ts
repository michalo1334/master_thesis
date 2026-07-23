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

  private loadToken = 0;

  constructor(graphTitle: string, graphId: string) {
    this.id = crypto.randomUUID();
    this.title = `Report for ${graphTitle}`;
    this.graphId = graphId;
  }

  markPending(correlationId: string): void {
    this.loadToken += 1;
    this.correlationId = correlationId;
    this.experimentId = null;
    this.status = "pending";
    this.reportData = null;
    this.errorReason = "";
  }

  markReady(experimentId: string): void {
    this.loadToken += 1;
    this.experimentId = experimentId;
    this.status = "ready";
    this.reportData = null;
    this.errorReason = "";
  }

  markError(reason: string): void {
    this.loadToken += 1;
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
    this.reportData = data;
    this.title = `Report for ${data.graph_title}`;
    this.status = "loaded";
  }

  complete(api: DashboardApi, experimentId: string, graphId: string): void {
    this.markReady(experimentId);
    void this.load(api, experimentId, graphId);
  }

  async load(
    api: DashboardApi,
    experimentId: string,
    graphId: string,
  ): Promise<void> {
    const loadToken = ++this.loadToken;
    this.experimentId = experimentId;
    this.status = "loading";
    this.errorReason = "";
    try {
      const reply = await api.fetchSimulationReport(experimentId, graphId);
      if (!this.isCurrentLoad(loadToken, experimentId)) return;
      if ("charts" in reply) {
        this.setReportData(reply);
      } else {
        this.status = "error";
        this.errorReason = reply.status || "Report not found.";
      }
    } catch {
      if (!this.isCurrentLoad(loadToken, experimentId)) return;
      this.status = "error";
      this.errorReason = "Failed to load report.";
    }
  }

  private isCurrentLoad(loadToken: number, experimentId: string): boolean {
    return this.loadToken === loadToken && this.experimentId === experimentId;
  }
}
