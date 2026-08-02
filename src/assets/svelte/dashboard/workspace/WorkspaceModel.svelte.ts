import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import type { DashboardApi } from "../dashboard-api";
import type {
  FolderSummary,
  GraphSummary,
  GraphDiffResult,
  LoadedGraph,
  ExperimentSummary,
  OptimizationRunSummary,
  OptimizationParams,
  SimulationParams,
  OptimizationStrategy,
} from "../contract";
import type { ForceParams } from "../graph/layout/ForceLayout.types";
import { defaultForceParams } from "../graph/layout/ForceLayout.types";
import { isReport, type WorkspaceDocument } from "./WorkspaceDocument.svelte";

export type { WorkspaceDocument } from "./WorkspaceDocument.svelte";

export interface FootholdHost {
  id: string;
  name: string;
}

export type OptimizationParamsChange = Omit<
  Partial<OptimizationParams>,
  "simulation_params"
> & {
  simulation_params?: Partial<SimulationParams>;
};

export class WorkspaceModel {
  /** Graphs available to open, owned by workspace so the picker has them. */
  graphSummaries = $state.raw<GraphSummary[]>([]);
  folders = $state.raw<FolderSummary[]>([]);

  documents = $state<WorkspaceDocument[]>([]);
  selectedDocumentId = $state<string | undefined>();

  topologyPickerOpen = $state(false);
  topologyPickerStatus = $state("");
  graphComparisonPickerOpen = $state(false);
  graphComparisonPickerStatus = $state("");
  graphComparisonBase = $state.raw<LoadedGraph>();
  experimentsModalOpen = $state(false);
  experiments = $state.raw<ExperimentSummary[]>([]);
  optimizationRuns = $state.raw<OptimizationRunSummary[]>([]);
  experimentsStatus = $state("");
  isLoadingExperiments = $state(false);
  private savedResultsRefreshQueued = false;

  forceParams = $state<ForceParams>({ ...defaultForceParams });
  simulationParams = $state<SimulationParams>({
    initial_foothold_node_id: "",
    monte_carlo_trials: 1000,
    iterations_per_run: 1000,
    max_attempts: 1,
    generate_seed: false,
    seed: 0,
  });
  optimizationParams = $state<
    OptimizationParams & { simulation_params: SimulationParams }
  >({
    strategy: "cvss",
    budget: 1,
    simulation_params: {
      initial_foothold_node_id: "",
      monte_carlo_trials: 1000,
      iterations_per_run: 1000,
      max_attempts: 1,
      generate_seed: false,
      seed: 0,
    },
  });
  statusMessage = $state("");

  constructor(
    graphSummaries: GraphSummary[] = [],
    folders: FolderSummary[] = [],
  ) {
    this.graphSummaries = graphSummaries;
    this.folders = folders;
  }

  upsertGraphSummary(graph: LoadedGraph): void {
    const previous = this.graphSummaries.find(
      ({ revision_id }) => revision_id === graph.revision_id,
    );
    const graphFolderId =
      previous?.folder_id ??
      this.graphSummaries.find(({ graph_id }) => graph_id === graph.id)
        ?.folder_id;
    const summary: GraphSummary = {
      graph_id: graph.id,
      title: graph.title,
      revision_id: graph.revision_id ?? "",
      parent_revision_id: graph.parent_revision_id ?? null,
      revision_kind: graph.revision_kind ?? "draft",
      revision_number: graph.revision_number ?? 0,
      node_count: graph.nodes.length,
      edge_count: graph.edges.length,
      is_favorite: previous?.is_favorite ?? false,
      ...(graphFolderId === undefined ? {} : { folder_id: graphFolderId }),
    };
    const index = this.graphSummaries.findIndex(
      ({ revision_id }) => revision_id === graph.revision_id,
    );
    this.graphSummaries =
      index === -1
        ? [...this.graphSummaries, summary]
        : this.graphSummaries.map((item, itemIndex) =>
            itemIndex === index ? summary : item,
          );
  }

  async createFolder(api: DashboardApi, name: string): Promise<boolean> {
    const trimmedName = name.trim();
    if (!trimmedName) {
      this.statusMessage = "Folder name is required.";
      return false;
    }

    this.statusMessage = "";
    try {
      const reply = await api.createFolder(trimmedName);
      if (reply.status !== "ok" || !reply.folder) {
        this.statusMessage = "Could not create folder.";
        return false;
      }

      this.folders = [
        ...this.folders.filter((folder) => folder.id !== reply.folder!.id),
        reply.folder,
      ];
      return true;
    } catch {
      this.statusMessage = "Could not create folder.";
      return false;
    }
  }

  async deleteFolder(api: DashboardApi, folderId: string): Promise<boolean> {
    this.statusMessage = "";
    try {
      const reply = await api.deleteFolder(folderId);
      if (reply.status !== "ok") {
        this.statusMessage = "Could not delete folder.";
        return false;
      }

      this.folders = this.folders.filter((folder) => folder.id !== folderId);
      this.graphSummaries = this.graphSummaries.map((summary) =>
        summary.folder_id === folderId
          ? { ...summary, folder_id: null }
          : summary,
      );
      return true;
    } catch {
      this.statusMessage = "Could not delete folder.";
      return false;
    }
  }

  async moveGraphToFolder(
    api: DashboardApi,
    graphId: string,
    folderId: string | null,
  ): Promise<boolean> {
    this.statusMessage = "";
    try {
      const reply = await api.moveGraphToFolder(graphId, folderId);
      if (reply.status !== "ok") {
        this.statusMessage = "Could not move graph.";
        return false;
      }

      this.graphSummaries = this.graphSummaries.map((summary) =>
        summary.graph_id === graphId
          ? { ...summary, folder_id: folderId }
          : summary,
      );
      return true;
    } catch {
      this.statusMessage = "Could not move graph.";
      return false;
    }
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
    return this.documents.some((d) => isReport(d) && d.hasUnread);
  }

  get hasActiveGraph(): boolean {
    return this.activeDocument?.kind === "graph";
  }

  get graphComparisonPickerTitle(): string {
    return this.graphComparisonBase ? "Compare with graph" : "Compare graphs";
  }

  get graphComparisonPickerDescription(): string {
    return this.graphComparisonBase
      ? `Select a graph to compare with ${this.graphComparisonBase.title}.`
      : "Select the base graph to compare.";
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
    if (doc && isReport(doc)) {
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
      (d) => d.kind === "graph" && d.loadedRevisionId === graph.revision_id,
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
      const reply = await api.openGraph(summary.revision_id);
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

  async setGraphRevisionFavorite(
    api: DashboardApi,
    summary: GraphSummary,
    favorite: boolean,
  ): Promise<boolean> {
    this.topologyPickerStatus = "";
    this.graphComparisonPickerStatus = "";
    try {
      const reply = await api.setGraphRevisionFavorite(
        summary.revision_id,
        favorite,
      );
      if (reply.status !== "ok") {
        this.setGraphFavoriteError(reply.status);
        return false;
      }

      const index = this.graphSummaries.findIndex(
        ({ revision_id }) => revision_id === summary.revision_id,
      );
      if (index !== -1) {
        this.graphSummaries = this.graphSummaries.map((item, itemIndex) =>
          itemIndex === index ? { ...item, is_favorite: reply.favorite } : item,
        );
      }
      return true;
    } catch {
      this.setGraphFavoriteError("unmapped_error");
      return false;
    }
  }

  beginGraphComparison(): void {
    this.graphComparisonBase = undefined;
    this.graphComparisonPickerStatus = "";
    this.graphComparisonPickerOpen = true;
  }

  beginGraphComparisonWithActive(document: EditableGraphDocument): void {
    if (!document.loadedRevisionId || document.isDirty) {
      this.statusMessage = "Save the graph before comparing it.";
      return;
    }

    const graph = $state.snapshot(document.graph);
    this.graphComparisonPickerStatus = "";
    this.upsertGraphSummary(graph);
    this.graphComparisonBase = graph;
    this.graphComparisonPickerOpen = true;
  }

  async selectGraphForComparison(
    api: DashboardApi,
    summary: GraphSummary,
  ): Promise<boolean> {
    this.graphComparisonPickerStatus = "";
    if (this.graphComparisonBase?.revision_id === summary.revision_id) {
      this.graphComparisonPickerStatus = "Select a different graph.";
      return false;
    }
    const base = this.graphComparisonBase;
    try {
      if (base) {
        const baseRevisionId = base.revision_id;
        if (!baseRevisionId) return false;
        const comparison = await api.compareGraphs(
          baseRevisionId,
          summary.revision_id,
        );
        if (comparison.status !== "ok" || !comparison.result) {
          this.graphComparisonPickerStatus =
            comparison.status === "not_found"
              ? "Comparison graph not found."
              : "Failed to compare graphs.";
          return false;
        }

        this.openGraphDiff(base, summary, comparison.result);
        this.graphComparisonPickerOpen = false;
        this.graphComparisonBase = undefined;
        return true;
      }

      const reply = await api.openGraph(summary.revision_id);
      if (reply.status !== "ok" || !reply.graph) {
        this.graphComparisonPickerStatus = "Failed to open graph.";
        return false;
      }
      this.upsertGraphSummary(reply.graph);
      this.graphComparisonBase = reply.graph;
      return false;
    } catch {
      this.graphComparisonPickerStatus = base
        ? "Failed to compare graphs."
        : "Failed to open graph.";
      return false;
    }
  }

  setGraphComparisonPickerOpen(open: boolean): void {
    this.graphComparisonPickerOpen = open;
    if (!open) {
      this.graphComparisonBase = undefined;
      this.graphComparisonPickerStatus = "";
    }
  }

  async openOptimizationResult(
    api: DashboardApi,
    graphRevisionId: string,
  ): Promise<boolean> {
    try {
      const reply = await api.openGraph(graphRevisionId);
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

  async loadOptimizationGraphDiff(
    api: DashboardApi,
    baseRevisionId: string,
    optimizedRevisionId: string,
  ): Promise<GraphDiffDocument | undefined> {
    try {
      const baseReply = await api.openGraph(baseRevisionId);
      if (baseReply.status !== "ok" || !baseReply.graph) return undefined;

      const comparison = await api.compareGraphs(
        baseRevisionId,
        optimizedRevisionId,
      );
      if (comparison.status !== "ok" || !comparison.result) return undefined;

      return new GraphDiffDocument(
        baseReply.graph,
        { revisionId: optimizedRevisionId, title: "Optimized graph" },
        comparison.result,
      );
    } catch {
      return undefined;
    }
  }

  async saveActiveGraph(api: DashboardApi): Promise<boolean> {
    const doc = this.activeGraph;
    if (!doc) return false;
    const saved = await doc.save(api);
    if (saved) this.upsertGraphSummary(doc.graph);
    this.statusMessage = doc.saveStatusMessage;
    return saved;
  }

  createPendingReport(info: {
    graphId: string;
    graphRevisionId: string;
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
      report = new SimulationReportDocument(
        info.graphTitle,
        info.graphId,
        info.graphRevisionId,
      );
      report.markPending(info.correlationId);
      this.documents.push(report);
    }
    this.selectedDocumentId = report.id;
    return report;
  }

  createPendingOptimizationReport(info: {
    graphId: string;
    graphRevisionId: string;
    graphTitle: string;
    correlationId: string;
    strategy: OptimizationStrategy;
    budget: number;
  }): OptimizationReportDocument {
    const existing = this.documents.find(
      (document) =>
        document.kind === "optimization-report" &&
        document.correlationId === info.correlationId,
    ) as OptimizationReportDocument | undefined;
    if (existing) {
      this.selectedDocumentId = existing.id;
      return existing;
    }

    const report = new OptimizationReportDocument(info);
    this.documents.push(report);
    this.selectedDocumentId = report.id;
    return report;
  }

  findOptimizationReport(
    correlationId: string,
    graphId: string,
  ): OptimizationReportDocument | undefined {
    return this.documents.find(
      (document) =>
        document.kind === "optimization-report" &&
        document.correlationId === correlationId &&
        document.graphId === graphId,
    ) as OptimizationReportDocument | undefined;
  }

  async loadSavedResults(api: DashboardApi): Promise<void> {
    if (this.isLoadingExperiments) {
      this.savedResultsRefreshQueued = true;
      return;
    }

    const graphRevisionIds = [
      ...new Set(this.graphSummaries.map(({ revision_id }) => revision_id)),
    ];
    if (graphRevisionIds.length === 0) {
      this.experiments = [];
      this.optimizationRuns = [];
      return;
    }

    this.isLoadingExperiments = true;
    try {
      const [experiments, optimizationRuns] = await Promise.all([
        api.fetchExperiments(graphRevisionIds),
        api.fetchOptimizationRuns(graphRevisionIds),
      ]);
      this.experiments = experiments.experiments;
      this.optimizationRuns = optimizationRuns.runs;
    } catch {
      this.experimentsStatus = "Failed to load saved results.";
    } finally {
      this.isLoadingExperiments = false;
      if (this.savedResultsRefreshQueued) {
        this.savedResultsRefreshQueued = false;
        await this.loadSavedResults(api);
      }
    }
  }

  async showExperiments(api: DashboardApi): Promise<void> {
    this.experimentsStatus = "";
    this.experimentsModalOpen = true;
    await this.loadSavedResults(api);
    if (!this.experimentsStatus && this.experiments.length === 0) {
      this.experimentsStatus = "No experiments found.";
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
        experiment.graph_revision_id,
      );
      report.markReady(experiment.id);
      this.documents.push(report);
    }

    this.selectedDocumentId = report.id;
    report.load(api, experiment.id, experiment.graph_revision_id);
    return true;
  }

  openOptimizationRun(api: DashboardApi, run: OptimizationRunSummary): boolean {
    const existing = this.documents.find(
      (d) => d.kind === "optimization-report" && d.optimizationId === run.id,
    ) as OptimizationReportDocument | undefined;
    const report =
      existing ??
      new OptimizationReportDocument({
        graphId: run.graph_id,
        graphRevisionId: run.graph_revision_id,
        graphTitle: run.graph_title,
        strategy: run.strategy as OptimizationStrategy,
        budget: run.requested_budget,
      });
    if (!existing) this.documents.push(report);

    report.markReady(
      run.id,
      run.output_graph_revision_id,
      () => this.openOptimizationResult(api, run.output_graph_revision_id),
      () =>
        this.loadOptimizationGraphDiff(
          api,
          run.graph_revision_id,
          run.output_graph_revision_id,
        ),
    );
    this.selectedDocumentId = report.id;
    report.load(api, run.id, run.graph_revision_id);
    return true;
  }

  onForceParamsChange(change: Partial<ForceParams>): void {
    Object.assign(this.forceParams, change);
  }

  onSimulationParamsChange(change: Partial<SimulationParams>): void {
    Object.assign(this.simulationParams, change);
  }

  onOptimizationParamsChange(change: OptimizationParamsChange): void {
    const simulationParams = change.simulation_params
      ? {
          ...this.optimizationParams.simulation_params,
          ...change.simulation_params,
        }
      : this.optimizationParams.simulation_params;
    Object.assign(this.optimizationParams, {
      ...change,
      simulation_params: simulationParams,
    });
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
    if (
      !hosts.some(
        (host) =>
          host.id ===
          this.optimizationParams.simulation_params.initial_foothold_node_id,
      )
    ) {
      this.optimizationParams.simulation_params.initial_foothold_node_id =
        hosts[0]?.id ?? "";
    }
  }

  private setGraphFavoriteError(
    status: "not_found" | "invalid_graph" | "unmapped_error",
  ): void {
    const message =
      status === "not_found"
        ? "Graph not found."
        : "Could not update favourite.";
    this.topologyPickerStatus = message;
    this.graphComparisonPickerStatus = message;
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

  private openGraphDiff(
    base: LoadedGraph,
    comparison: GraphSummary,
    result: GraphDiffResult,
  ): GraphDiffDocument {
    const document = new GraphDiffDocument(
      base,
      { revisionId: comparison.revision_id, title: comparison.title },
      result,
    );
    this.documents.push(document);
    this.selectedDocumentId = document.id;
    return document;
  }
}
