import type {
  DashboardError,
  LoadedGraph,
  SimulationReportData,
} from "../contract";
import type { DashboardApi } from "../dashboard-api";
import { formatDashboardErrorCode } from "../error-code";
import type { ClientReportEvent, EventResult } from "../report-events";
import type { IconName } from "../types";
import { AsyncReportDocument } from "../workspace/WorkspaceDocument.svelte";

export class SimulationReportDocument extends AsyncReportDocument {
  readonly kind = "simulation-report" as const;
  readonly icon = "simulation-report" as const satisfies IconName;
  readonly id: string;
  readonly graphId: string;
  readonly graphRevisionId: string;

  title = $state<string>("");
  status = $state<"pending" | "ready" | "loading" | "loaded" | "error">(
    "pending",
  );
  hasUnread = $state(false);
  experimentId = $state<string | null>(null);
  correlationId = $state<string | null>(null);
  reportData = $state<SimulationReportData | null>(null);
  heatmapGraph = $state<LoadedGraph | null>(null);
  heatmapSelectedNodeId = $state<string>();
  heatmapSelectedEdgeId = $state<string>();
  errorReason = $state<string>("");
  completedRuns = $state(0);
  totalRuns = $state(0);

  constructor(graphTitle: string, graphId: string, graphRevisionId: string) {
    super();
    this.id = crypto.randomUUID();
    this.title = `Report for ${graphTitle}`;
    this.graphId = graphId;
    this.graphRevisionId = graphRevisionId;
  }

  markPending(correlationId: string): void {
    this.correlationId = correlationId;
    this.experimentId = null;
    this.status = "pending";
    this.reportData = null;
    this.heatmapGraph = null;
    this.clearHeatmapSelection();
    this.errorReason = "";
    this.completedRuns = 0;
    this.totalRuns = 0;
  }

  markReady(experimentId: string): void {
    this.experimentId = experimentId;
    this.status = "ready";
    this.reportData = null;
    this.heatmapGraph = null;
    this.clearHeatmapSelection();
    this.errorReason = "";
    this.completedRuns = 0;
    this.totalRuns = 0;
  }

  setProgress(completedRuns: number, totalRuns: number): void {
    if (this.status !== "pending") return;
    this.completedRuns = completedRuns;
    this.totalRuns = totalRuns;
  }

  markError(error: DashboardError): void {
    this.markErrorMessage(formatDashboardErrorCode(error.code));
  }

  markErrorMessage(message: string): void {
    this.status = "error";
    this.errorReason = message;
  }

  markRead(): void {
    this.hasUnread = false;
  }

  markUnread(): void {
    this.hasUnread = true;
  }

  selectHeatmapNode(nodeId: string): void {
    this.heatmapSelectedNodeId = nodeId;
    this.heatmapSelectedEdgeId = undefined;
  }

  selectHeatmapEdge(edgeId: string): void {
    this.heatmapSelectedNodeId = undefined;
    this.heatmapSelectedEdgeId = edgeId;
  }

  clearHeatmapSelection(): void {
    this.heatmapSelectedNodeId = undefined;
    this.heatmapSelectedEdgeId = undefined;
  }

  setReportData(data: SimulationReportData): void {
    if (data.experiment_id !== this.experimentId) return;
    this.reportData = data;
    this.heatmapGraph = {
      ...data.graph,
      nodes: data.graph.nodes.map((node) => ({
        ...node,
        view_data: { ...node.view_data },
      })),
    };
    this.clearHeatmapSelection();
    this.title = `Report for ${data.graph_title}`;
    this.status = "loaded";
  }

  accept(event: ClientReportEvent): EventResult {
    return event.visitSimulation(this);
  }

  complete(
    api: DashboardApi,
    experimentId: string,
    graphRevisionId: string,
  ): void {
    this.markReady(experimentId);
    this.load(api, this.id, experimentId, graphRevisionId);
  }

  load(
    api: DashboardApi,
    documentId: string,
    experimentId: string,
    graphRevisionId: string,
  ): void {
    this.experimentId = experimentId;
    this.status = "loading";
    this.errorReason = "";
    api.requestReport({
      type: "simulation",
      documentId,
      reportId: experimentId,
      graphRevisionId,
    });
  }
}
