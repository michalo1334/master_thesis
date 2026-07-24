import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { DashboardApi } from "../dashboard-api";
import type {
  GraphSummary,
  LoadedGraph,
  ExperimentSummary,
  SimulationParams,
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
  experimentsModalOpen = $state(false);
  experiments = $state<ExperimentSummary[]>([]);
  experimentsStatus = $state("");
  isLoadingExperiments = $state(false);

  forceParams = $state<ForceParams>({ ...defaultForceParams });
  simulationParams = $state<SimulationParams>({
    monte_carlo_trials: 1000,
    iterations_per_run: 1000,
    generate_seed: false,
    seed: 0,
  });
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

  async openGraph(api: DashboardApi, summary: GraphSummary): Promise<boolean> {
    this.topologyPickerStatus = "";
    try {
      const reply = await api.openGraph(summary.id);
      if (reply.status === "ok" && reply.graph) {
        this.openLoadedGraph(reply.graph, api);
        return true;
      }

      this.topologyPickerStatus =
        reply.status === "not_found"
          ? "Topology not found."
          : "Failed to open topology.";
      return false;
    } catch {
      this.topologyPickerStatus = "Failed to open topology.";
      return false;
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

  async showExperiments(api: DashboardApi): Promise<void> {
    if (this.isLoadingExperiments) return;

    const graphIds = this.documents
      .filter((d) => d.kind === "graph")
      .map((d) => (d as EditableGraphDocument).loadedGraphId!)
      .filter(Boolean);

    if (graphIds.length === 0) return;

    this.experimentsStatus = "";
    this.experimentsModalOpen = true;
    this.isLoadingExperiments = true;
    try {
      const reply = await api.fetchExperiments(graphIds);
      this.experiments = reply.experiments;
      if (reply.experiments.length === 0) {
        this.experimentsStatus = "No experiments found.";
      }
    } catch {
      this.experimentsStatus = "Failed to load experiments.";
    } finally {
      this.isLoadingExperiments = false;
    }
  }

  async selectExperiment(
    api: DashboardApi,
    experiment: ExperimentSummary,
  ): Promise<boolean> {
    const existing = this.documents.find(
      (d) => d.kind === "simulation-report" && d.experimentId === experiment.id,
    ) as SimulationReportDocument | undefined;

    let report: SimulationReportDocument;
    if (existing) {
      report = existing;
      existing.markReady(experiment.id);
    } else {
      report = new SimulationReportDocument(
        experiment.graph_title,
        experiment.graph_id,
      );
      report.markReady(experiment.id);
      this.documents.push(report);
    }

    this.selectedDocumentId = report.id;
    report.load(api, experiment.id, experiment.graph_id);
    return true;
  }

  onForceParamsChange(change: Partial<ForceParams>): void {
    Object.assign(this.forceParams, change);
  }

  onSimulationParamsChange(change: Partial<SimulationParams>): void {
    Object.assign(this.simulationParams, change);
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
