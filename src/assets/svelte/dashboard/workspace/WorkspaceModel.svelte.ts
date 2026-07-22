import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { DashboardApi } from "../dashboard-api";
import type {
  GraphSummary,
  LoadedGraph,
  SimulationRunSummary,
} from "../contract";
import type { ForceParams } from "../graph/layout/ForceLayout.types";
import { defaultForceParams } from "../graph/layout/ForceLayout.types";

export type WorkspaceDocument =
  EditableGraphDocument | SimulationReportDocument;

export class WorkspaceModel {
  /** Topologies available to open, owned by workspace so the picker has them. */
  graphSummaries: GraphSummary[];

  documents = $state<WorkspaceDocument[]>([]);
  selectedDocumentId = $state<string | undefined>();

  topologyPickerOpen = $state(false);
  topologyPickerStatus = $state("");
  simulationRunsModalOpen = $state(false);
  simulationRuns = $state<SimulationRunSummary[]>([]);
  simulationRunsStatus = $state("");
  isLoadingSimulationRuns = $state(false);

  forceParams = $state<ForceParams>({ ...defaultForceParams });
  statusMessage = $state("");

  constructor(graphSummaries: GraphSummary[] = []) {
    this.graphSummaries = graphSummaries;
  }

  get activeDocument(): WorkspaceDocument | undefined {
    return this.documents.find((d) => d.id === this.selectedDocumentId);
  }

  get activeGraph(): EditableGraphDocument | undefined {
    const doc = this.activeDocument;
    if (doc?.kind === "graph") return doc;
    return undefined;
  }

  get hasUnreadReport(): boolean {
    return this.documents.some(
      (d) => d.kind === "simulation-report" && d.hasUnread,
    );
  }

  get hasActiveGraph(): boolean {
    return this.activeDocument?.kind === "graph";
  }

  createGraphDocument(title?: string): EditableGraphDocument {
    const doc = new EditableGraphDocument();
    this.documents.push(doc);
    this.selectedDocumentId = doc.id;
    return doc;
  }

  selectDocument(id: string): void {
    this.selectedDocumentId = id;
    const doc = this.activeDocument;
    if (doc?.kind === "simulation-report") {
      doc.markRead();
    }
  }

  closeDocument(id: string): void {
    const currentIdx = this.documents.findIndex((d) => d.id === id);
    if (currentIdx === -1) return;

    this.documents = this.documents.filter((d) => d.id !== id);

    if (this.selectedDocumentId === id) {
      if (this.documents.length === 0) {
        this.selectedDocumentId = undefined;
      } else {
        const nextIdx = currentIdx > 0 ? currentIdx - 1 : 0;
        this.selectedDocumentId = this.documents[nextIdx]?.id;
      }
    }
  }

  async openLoadedGraph(
    graph: LoadedGraph,
    api: DashboardApi,
  ): Promise<EditableGraphDocument | undefined> {
    const existing = this.documents.find(
      (d) => d.kind === "graph" && d.loadedGraphId === graph.id,
    ) as EditableGraphDocument | undefined;
    if (existing) {
      this.selectedDocumentId = existing.id;
      return undefined;
    }

    const blankDoc = this.documents.find(
      (d) => d.kind === "graph" && !d.loaded,
    ) as EditableGraphDocument | undefined;

    if (blankDoc) {
      blankDoc.replaceFromLoadedGraph(graph);
      this.selectedDocumentId = blankDoc.id;
      return blankDoc;
    }

    const doc = new EditableGraphDocument();
    doc.replaceFromLoadedGraph(graph);
    this.documents.push(doc);
    this.selectedDocumentId = doc.id;
    return doc;
  }

  async openGraph(api: DashboardApi, summary: GraphSummary): Promise<void> {
    this.topologyPickerStatus = "";
    const reply = await api.openGraph(summary.id);
    if (reply.status === "ok" && reply.graph) {
      this.openLoadedGraph(reply.graph, api);
      this.topologyPickerOpen = false;
    } else {
      this.topologyPickerStatus =
        reply.status === "not_found"
          ? "Topology not found."
          : "Failed to open topology.";
    }
  }

  async saveActiveGraph(api: DashboardApi): Promise<void> {
    const doc = this.activeGraph;
    if (!doc) return;
    await doc.save(api);
    this.statusMessage = doc.saveStatusMessage;
  }

  createPendingReport(info: {
    graphId: string;
    correlationId: string;
    graphTitle: string;
  }): SimulationReportDocument {
    const existing = this.documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        d.correlationId === info.correlationId,
    ) as SimulationReportDocument | undefined;

    let report: SimulationReportDocument;
    if (existing) {
      report = existing;
      report.markPending(info.correlationId);
    } else {
      report = new SimulationReportDocument(info.graphTitle, info.graphId);
      report.markPending(info.correlationId);
      this.documents.push(report);
    }
    this.selectedDocumentId = report.id;
    return report;
  }

  async showReport(api: DashboardApi): Promise<void> {
    if (this.isLoadingSimulationRuns) return;

    const graphIds = this.documents
      .filter((d) => d.kind === "graph")
      .map((d) => (d as EditableGraphDocument).loadedGraphId!)
      .filter(Boolean);

    if (graphIds.length === 0) return;

    this.simulationRunsStatus = "";
    this.simulationRunsModalOpen = true;
    this.isLoadingSimulationRuns = true;
    try {
      const reply = await api.fetchSimulationRuns(graphIds);
      this.simulationRuns = reply.runs;
      if (reply.runs.length === 0) {
        this.simulationRunsStatus = "No simulation runs found.";
      }
    } catch {
      this.simulationRunsStatus = "Failed to load simulation runs.";
    } finally {
      this.isLoadingSimulationRuns = false;
    }
  }

  async selectSimulationRun(
    api: DashboardApi,
    run: SimulationRunSummary,
  ): Promise<void> {
    this.simulationRunsModalOpen = false;

    const existing = this.documents.find(
      (d) => d.kind === "simulation-report" && d.simulationId === run.id,
    ) as SimulationReportDocument | undefined;

    let report: SimulationReportDocument;
    if (existing) {
      report = existing;
      existing.markReady(run.id);
    } else {
      report = new SimulationReportDocument(run.graph_title, run.graph_id);
      report.markReady(run.id);
      this.documents.push(report);
    }

    this.selectedDocumentId = report.id;
    report.load(api, run.id, run.graph_id);
  }

  onForceParamsChange(change: Partial<ForceParams>): void {
    Object.assign(this.forceParams, change);
  }

  applyForceLayout(): void {
    const doc = this.activeGraph;
    if (!doc) return;
    doc.applyForceLayout(this.forceParams);
  }

  handleCreateDocument(typeId: string): void {
    if (typeId === "graph") {
      this.topologyPickerOpen = true;
      this.topologyPickerStatus = "";
    }
  }
}
