import type { SimulationReportData } from "../contract";
import type { DocumentBase } from "../workspace/WorkspaceDocument.svelte";
import { registerDocument } from "../workspace/WorkspaceDocument.svelte";

export class SimulationReportDocument implements DocumentBase {
  readonly kind = "simulation-report" as const;
  readonly id: string;
  readonly graphId: string;

  title = $state<string>("");
  status = $state<"waiting" | "ready" | "empty">("empty");
  hasUnread = $state(false);
  multiStateId = $state<string | null>(null);
  reportData = $state<SimulationReportData | null>(null);

  constructor(graphTitle: string, graphId: string) {
    this.id = crypto.randomUUID();
    this.title = `Report for ${graphTitle}`;
    this.graphId = graphId;
  }

  markWaiting(): void {
    this.status = "waiting";
    this.reportData = null;
  }

  markReady(multiStateId: string): void {
    this.multiStateId = multiStateId;
    this.status = "ready";
  }

  markRead(): void {
    this.hasUnread = false;
  }

  setReportData(data: SimulationReportData): void {
    this.reportData = data;
    this.title = `Report for ${data.graph_title}`;
  }
}

registerDocument(
  "simulation-report",
  (graphTitle: string, graphId: string) =>
    new SimulationReportDocument(graphTitle, graphId),
);
