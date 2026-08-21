import type { LoadedGraph, SimulationReportData } from "../contract";
import type { DashboardApi } from "../dashboard-api";
import { AsyncReportDocument } from "../workspace/WorkspaceDocument.svelte";
import type { DashboardRecoveryContext } from "../workspace/recovery-context";
import {
  isPersistedDocumentOfKind,
  type PersistedWorkspaceDocument,
} from "../../ui-kit/workspace/workspace-persistence";

export class SimulationReportDocument extends AsyncReportDocument<"simulation"> {
  readonly kind = "simulation-report" as const;
  readonly documentLabel = "Report";
  readonly reportKind = "simulation" as const;
  readonly icon = "simulation-report" as const satisfies string;

  get reportId(): string | null {
    return this.experimentId;
  }

  get reportApiKind(): "simulation_report" | "optimization_report" {
    return "simulation_report";
  }
  readonly id: string;
  graphId = $state("");
  graphRevisionId = $state("");

  experimentId = $state<string | null>(null);
  correlationId = $state<string | null>(null);
  reportData = $state<SimulationReportData | null>(null);
  heatmapGraph = $state<LoadedGraph | null>(null);
  heatmapSelectedNodeId = $state<string>();
  heatmapSelectedEdgeId = $state<string>();

  constructor(
    graphTitle: string,
    graphId: string,
    graphRevisionId: string,
    analysis: { analysisId?: string; analysisTitle?: string } = {},
  ) {
    super();
    this.id = crypto.randomUUID();
    this.title = `Report for ${graphTitle}`;
    this.graphId = graphId;
    this.graphRevisionId = graphRevisionId;
    this.analysisId = analysis.analysisId;
    this.analysisTitle = analysis.analysisTitle;
  }

  static fromPersisted(
    data: unknown,
    _context: DashboardRecoveryContext,
  ): SimulationReportDocument | undefined {
    if (!isSimulationReportPersisted(data)) return undefined;
    const report = new SimulationReportDocument(
      data.title,
      data.ids.graphId,
      data.ids.graphRevisionId,
    );
    report.title = data.title;
    report.markReady(data.ids.experimentId);
    report.setPersisted(data);
    return report;
  }

  toPersisted(): PersistedWorkspaceDocument | undefined {
    if (!this.experimentId) return undefined;
    return {
      kind: "simulation-report",
      ids: {
        experimentId: this.experimentId,
        graphId: this.graphId,
        graphRevisionId: this.graphRevisionId,
      },
      title: this.title,
    };
  }

  recover(context: DashboardRecoveryContext): void {
    const persisted = this.persistedData as
      PersistedSimulationReport | undefined;
    if (!persisted) return;
    this.load(context.api, this.id, persisted.ids.experimentId);
  }

  markPending(correlationId: string): void {
    this.correlationId = correlationId;
    this.experimentId = null;
    this.status = "pending";
    this.reportData = null;
    this.heatmapGraph = null;
    this.clearHeatmapSelection();
    this.errorReason = "";
    this.progress = null;
  }

  markReady(experimentId: string): void {
    this.experimentId = experimentId;
    this.status = "ready";
    this.reportData = null;
    this.heatmapGraph = null;
    this.clearHeatmapSelection();
    this.errorReason = "";
    this.progress = null;
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
    this.graphId = data.graph_id;
    this.graphRevisionId = data.graph_revision_id;
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

  complete(api: DashboardApi, experimentId: string): void {
    this.markReady(experimentId);
    this.load(api, this.id, experimentId);
  }

  load(api: DashboardApi, documentId: string, experimentId: string): void {
    this.experimentId = experimentId;
    this.status = "loading";
    this.loadProgress = null;
    this.errorReason = "";
    api.requestSimulationReport(documentId, experimentId);
  }
}

type PersistedSimulationReport = PersistedWorkspaceDocument & {
  ids: {
    experimentId: string;
    graphId: string;
    graphRevisionId: string;
  };
};

function isSimulationReportPersisted(
  value: unknown,
): value is PersistedSimulationReport {
  return isPersistedDocumentOfKind<PersistedSimulationReport["ids"]>(
    value,
    "simulation-report",
    ["experimentId", "graphId", "graphRevisionId"],
  );
}
