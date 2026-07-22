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
  simulationId = $state<string | null>(null);
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
    this.simulationId = null;
    this.status = "pending";
    this.reportData = null;
    this.errorReason = "";
  }

  markReady(simulationId: string): void {
    this.loadToken += 1;
    this.simulationId = simulationId;
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

  complete(api: DashboardApi, simulationId: string, graphId: string): void {
    this.markReady(simulationId);
    void this.load(api, simulationId, graphId);
  }

  async load(
    api: DashboardApi,
    simulationId: string,
    graphId: string,
  ): Promise<void> {
    const loadToken = ++this.loadToken;
    this.simulationId = simulationId;
    this.status = "loading";
    this.errorReason = "";
    try {
      const reply = await api.fetchSimulationReport(simulationId, graphId);
      if (!this.isCurrentLoad(loadToken, simulationId)) return;
      if ("charts" in reply) {
        this.setReportData(reply);
      } else {
        this.status = "error";
        this.errorReason = reply.status || "Report not found.";
      }
    } catch {
      if (!this.isCurrentLoad(loadToken, simulationId)) return;
      this.status = "error";
      this.errorReason = "Failed to load report.";
    }
  }

  private isCurrentLoad(loadToken: number, simulationId: string): boolean {
    return this.loadToken === loadToken && this.simulationId === simulationId;
  }
}
