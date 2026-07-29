import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { DashboardApi } from "../dashboard-api";
import type {
  GraphSummary,
  LoadedGraph,
  ExperimentSummary,
  OptimizationParams,
  SimulationParams,
} from "../contract";
import type { ForceParams } from "../graph/layout/ForceLayout.types";
import { defaultForceParams } from "../graph/layout/ForceLayout.types";

export type WorkspaceDocument =
  EditableGraphDocument | SimulationReportDocument;

export interface FootholdHost {
  id: string;
  name: string;
}

export interface OptimizationPending {
  graphId: string;
  correlationId: string;
}

export class WorkspaceModel {
  /** Graphs available to open, owned by workspace so the picker has them. */
  graphSummaries = $state.raw<GraphSummary[]>([]);

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
    initial_foothold_node_id: "",
    monte_carlo_trials: 1000,
    iterations_per_run: 1000,
    max_attempts: 1,
    generate_seed: false,
    seed: 0,
  });
  optimizationParams = $state<OptimizationParams>({
    strategy: "cvss",
    budget: 1,
  });
  optimizationPending = $state<OptimizationPending | null>(null);
  statusMessage = $state("");

  constructor(graphSummaries: GraphSummary[] = []) {
    this.graphSummaries = graphSummaries;
  }

  upsertGraphSummary(graph: LoadedGraph): void {
    const summary: GraphSummary = {
      id: graph.id,
      title: graph.title,
      parentId: graph.parent_id ?? null,
      tags: graph.tags,
      nodeCount: graph.nodes.length,
      edgeCount: graph.edges.length,
    };
    const index = this.graphSummaries.findIndex(({ id }) => id === graph.id);
    this.graphSummaries =
      index === -1
        ? [...this.graphSummaries, summary]
        : this.graphSummaries.map((item, itemIndex) =>
            itemIndex === index ? summary : item,
          );
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

  get isOptimizationPending(): boolean {
    return this.optimizationPending !== null;
  }

  get activeFootholdHosts(): FootholdHost[] {
    const graph = this.activeGraph?.graph;
    if (!graph) return [];

    return graph.nodes.flatMap((node) =>
      node.type === "Host" ? [{ id: node.id, name: node.data.name }] : [],
    );
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
    this.ensureInitialFoothold(doc);
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
    this.upsertGraphSummary(graph);
    const existing = this.documents.find(
      (d) => d.kind === "graph" && d.loadedGraphId === graph.id,
    ) as EditableGraphDocument | undefined;
    if (existing) {
      this.selectedDocumentId = existing.id;
      this.ensureInitialFoothold(existing);
      return undefined;
    }

    const blankDoc = this.documents.find(
      (d) => d.kind === "graph" && !d.loaded,
    ) as EditableGraphDocument | undefined;

    if (blankDoc) {
      blankDoc.replaceFromLoadedGraph(graph);
      this.selectedDocumentId = blankDoc.id;
      this.ensureInitialFoothold(blankDoc);
      return blankDoc;
    }

    const doc = new EditableGraphDocument();
    doc.replaceFromLoadedGraph(graph);
    this.documents.push(doc);
    this.selectedDocumentId = doc.id;
    this.ensureInitialFoothold(doc);
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

  async openOptimizationResult(
    api: DashboardApi,
    graphId: string,
  ): Promise<boolean> {
    try {
      const reply = await api.openGraph(graphId);
      if (reply.status !== "ok" || !reply.graph) {
        this.statusMessage = "Failed to open optimized graph.";
        return false;
      }
      await this.openLoadedGraph(reply.graph, api);
      this.statusMessage = "Optimization completed.";
      return true;
    } catch {
      this.statusMessage = "Failed to open optimized graph.";
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
      .flatMap((document) =>
        document.kind === "graph" && document.loadedGraphId
          ? [document.loadedGraphId]
          : [],
      )
      .filter((id, index, ids) => ids.indexOf(id) === index);

    this.experimentsStatus = "";
    this.experimentsModalOpen = true;
    if (graphIds.length === 0) {
      this.experiments = [];
      this.experimentsStatus = "No experiments found.";
      return;
    }

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

  onOptimizationParamsChange(change: Partial<OptimizationParams>): void {
    Object.assign(this.optimizationParams, change);
  }

  beginOptimization(pending: OptimizationPending): boolean {
    if (this.optimizationPending) return false;
    this.optimizationPending = pending;
    return true;
  }

  confirmOptimization(pending: OptimizationPending): void {
    this.optimizationPending = pending;
  }

  finishOptimization(correlationId: string, graphId: string): boolean {
    const pending = this.optimizationPending;
    if (
      !pending ||
      pending.correlationId !== correlationId ||
      pending.graphId !== graphId
    ) {
      return false;
    }
    this.optimizationPending = null;
    return true;
  }

  cancelOptimization(correlationId: string): void {
    if (this.optimizationPending?.correlationId === correlationId) {
      this.optimizationPending = null;
    }
  }

  private ensureInitialFoothold(document: WorkspaceDocument | undefined): void {
    if (document?.kind !== "graph") return;

    const hosts = document.graph.nodes.filter((node) => node.type === "Host");
    if (
      !hosts.some(
        (host) => host.id === this.simulationParams.initial_foothold_node_id,
      )
    ) {
      this.simulationParams.initial_foothold_node_id = hosts[0]?.id ?? "";
    }
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
