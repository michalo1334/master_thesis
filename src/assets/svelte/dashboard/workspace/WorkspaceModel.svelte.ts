import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import { AnalysisReportDocument } from "../analysis-report/AnalysisReportDocument.svelte";
import { DocumentCatalogDocument } from "../document-catalog/DocumentCatalogDocument.svelte";
import { RunsDocument } from "../runs/RunsDocument.svelte";
import type { DashboardApi } from "../dashboard-api";
import type {
  FolderSummary,
  GraphSummary,
  GraphDiffResult,
  LoadedGraph,
  OptimizationParams,
  OptimizationParamsChange,
  SimulationParams,
  OptimizationStrategy,
  DocumentCatalogItem,
} from "../contract";
import type { ForceParams } from "../graph/layout/ForceLayout.types";
import { defaultForceParams } from "../graph/layout/ForceLayout.types";
import { isReport, type WorkspaceDocument } from "./WorkspaceDocument.svelte";
import { GenericWorkspaceModel } from "../../ui-kit/workspace/WorkspaceModel.svelte";
import { dashboardRegistry } from "./dashboard-registry";
import type { DashboardRecoveryContext } from "./recovery-context";
import {
  isDashboardWorkspaceState,
  type DashboardWorkspaceState,
} from "./persisted-documents";
import type { WorkspaceEnvelope } from "../../ui-kit/workspace/workspace-persistence";

export type { WorkspaceDocument } from "./WorkspaceDocument.svelte";
export type { OptimizationParamsChange } from "../contract";

// ponytail: extends kit GenericWorkspaceModel - domain fields stay here per Option A.
export interface FootholdHost {
  id: string;
  name: string;
}

export class WorkspaceModel extends GenericWorkspaceModel<
  WorkspaceDocument,
  DashboardWorkspaceState,
  DashboardRecoveryContext
> {
  /** Graphs available to open, owned by workspace so the picker has them. */
  graphSummaries = $state.raw<GraphSummary[]>([]);
  folders = $state.raw<FolderSummary[]>([]);

  topologyPickerOpen = $state(false);
  topologyPickerStatus = $state("");
  graphComparisonPickerOpen = $state(false);
  graphComparisonPickerStatus = $state("");
  graphComparisonBase = $state.raw<LoadedGraph>();
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

  readonly documentTypes = Object.values(dashboardRegistry).flatMap(
    (registration) =>
      registration.createOption ? [registration.createOption] : [],
  );

  private readonly api?: DashboardApi;

  constructor(
    graphSummaries: GraphSummary[] = [],
    folders: FolderSummary[] = [],
    api?: DashboardApi,
  ) {
    super();
    this.graphSummaries = graphSummaries;
    this.folders = folders;
    this.api = api;
    this.configurePersistence({
      version: 1,
      snapshotState: () => this.snapshotState(),
      restoreState: (state) => this.restoreState(state),
      validateState: isDashboardWorkspaceState,
      documentFactory: new Map(
        Object.entries(dashboardRegistry).flatMap(([kind, registration]) =>
          registration.fromPersisted
            ? [[kind, registration.fromPersisted]]
            : [],
        ),
      ) as ReadonlyMap<
        string,
        (
          data: unknown,
          context: DashboardRecoveryContext,
        ) => WorkspaceDocument | undefined
      >,
      recoveryContext: { api: api!, workspace: this },
    });
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
    this.activateDocument(doc);
    return doc;
  }

  openDocumentCatalog(): DocumentCatalogDocument {
    const existing = this.documents.find(
      (document) => document.kind === "document-catalog",
    ) as DocumentCatalogDocument | undefined;
    if (existing) {
      this.activateDocument(existing);
      return existing;
    }

    const document = this.createCatalogDocument();
    this.documents.push(document);
    this.activateDocument(document);
    return document;
  }

  private createCatalogDocument(): DocumentCatalogDocument {
    const api = this.api;
    return new DocumentCatalogDocument(
      api ? (item) => this.openCatalogItem(api, item) : undefined,
    );
  }

  openRuns(): RunsDocument {
    const existing = this.documents.find(
      (document) => document.kind === "runs",
    ) as RunsDocument | undefined;
    if (existing) {
      this.activateDocument(existing);
      return existing;
    }

    const document = new RunsDocument();
    this.documents.push(document);
    this.activateDocument(document);
    return document;
  }

  selectDocument(id: string): void {
    super.selectDocument(id);
    this.activateDocument(this.activeDocument);
  }

  toPersistence(): WorkspaceEnvelope<DashboardWorkspaceState> | undefined {
    return this.snapshot();
  }

  restorePersistence(
    persistence: WorkspaceEnvelope<DashboardWorkspaceState> | undefined,
  ): void {
    this.restore(persistence);
  }

  reorderDocuments(draggedId: string, targetId: string): void {
    super.reorderDocuments(draggedId, targetId);
  }

  activateDocument(document: WorkspaceDocument | undefined): void {
    this.selectedDocumentId = document?.id;
    this.ensureInitialFoothold(document);
    if (document && isReport(document)) document.markRead();
  }

  canCloseDocument(document: WorkspaceDocument): boolean {
    return document.canClose();
  }

  closeDocument(id: string): void {
    super.closeDocument(id);
    this.activateDocument(this.activeDocument);
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
      this.activateDocument(existing);
      return undefined;
    }

    const blankDoc = this.documents.find(
      (d) => d.kind === "graph" && !d.loaded,
    ) as EditableGraphDocument | undefined;

    if (blankDoc) {
      blankDoc.replaceFromLoadedGraph(graph);
      this.activateDocument(blankDoc);
      return blankDoc;
    }

    const doc = new EditableGraphDocument();
    doc.replaceFromLoadedGraph(graph);
    this.documents.push(doc);
    this.activateDocument(doc);
    return doc;
  }

  async openGraph(api: DashboardApi, summary: GraphSummary): Promise<boolean> {
    this.topologyPickerStatus = "";
    const existing = this.findOpenGraph(summary.revision_id);
    if (existing) {
      this.activateDocument(existing);
      return true;
    }

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

  async openGraphRevision(
    api: DashboardApi,
    graphRevisionId: string,
  ): Promise<boolean> {
    this.statusMessage = "";
    const existing = this.findOpenGraph(graphRevisionId);
    if (existing) {
      this.activateDocument(existing);
      return true;
    }

    try {
      const reply = await api.openGraph(graphRevisionId);
      if (reply.status !== "ok" || !reply.graph) {
        this.statusMessage = "Failed to open graph.";
        return false;
      }

      await this.openLoadedGraph(reply.graph, api);
      return true;
    } catch {
      this.statusMessage = "Failed to open graph.";
      return false;
    }
  }

  private readonly catalogOpeners: Record<
    DocumentCatalogItem["kind"],
    (api: DashboardApi, item: DocumentCatalogItem) => Promise<boolean> | boolean
  > = {
    graph: (api, item) => this.openGraphRevision(api, item.graph_revision_id),
    simulation_report: (api, item) =>
      this.openHistoricalSimulationReport(api, item),
    optimization_report: (api, item) =>
      this.openHistoricalOptimizationReport(api, item),
    analysis_report: (api, item) =>
      this.openHistoricalAnalysisReport(api, item),
  };

  async openCatalogItem(
    api: DashboardApi,
    item: DocumentCatalogItem,
  ): Promise<boolean> {
    const opener = this.catalogOpeners[item.kind];
    return opener ? opener(api, item) : false;
  }

  openHistoricalSimulationReport(
    api: DashboardApi,
    item: DocumentCatalogItem,
  ): boolean {
    const existing = this.documents.find(
      (document) =>
        document.kind === "simulation-report" &&
        document.experimentId === item.id,
    ) as SimulationReportDocument | undefined;
    if (existing) {
      this.activateDocument(existing);
      return true;
    }

    const report = new SimulationReportDocument(
      item.graph_title,
      item.graph_id,
      item.graph_revision_id,
    );
    this.documents.push(report);
    this.activateDocument(report);
    report.load(api, report.id, item.id);
    return true;
  }

  openHistoricalOptimizationReport(
    api: DashboardApi,
    item: DocumentCatalogItem,
  ): boolean {
    const existing = this.documents.find(
      (document) =>
        document.kind === "optimization-report" &&
        document.optimizationId === item.id,
    ) as OptimizationReportDocument | undefined;
    if (existing) {
      this.activateDocument(existing);
      return true;
    }

    const report = new OptimizationReportDocument({
      graphId: item.graph_id,
      graphRevisionId: item.graph_revision_id,
      graphTitle: item.graph_title,
      strategy: catalogOptimizationStrategy(item.strategy),
      budget: 0,
    });
    this.documents.push(report);
    this.activateDocument(report);
    if (item.output_graph_revision_id) {
      report.markReady(
        item.id,
        item.output_graph_revision_id,
        () => this.openOptimizationResult(api, item.output_graph_revision_id!),
        () =>
          this.loadOptimizationGraphDiff(
            api,
            report.graphRevisionId,
            item.output_graph_revision_id!,
          ),
      );
    }
    report.load(api, report.id, item.id);
    return true;
  }

  openHistoricalAnalysisReport(
    api: DashboardApi,
    item: DocumentCatalogItem,
  ): boolean {
    if (!item.manifest_id || !item.manifest_title) return false;
    const existing = this.documents.find(
      (document) =>
        document.kind === "analysis-report" && document.runId === item.id,
    ) as AnalysisReportDocument | undefined;
    if (existing) {
      this.bindAnalysisReportNavigation(existing, api);
      this.activateDocument(existing);
      return true;
    }

    const report = this.openPendingAnalysisReport(item.id, {
      manifest_id: item.manifest_id,
      title: item.manifest_title,
    });
    this.bindAnalysisReportNavigation(report, api);
    report.graphId = item.graph_id;
    report.graphRevisionId = item.graph_revision_id;
    report.load(api, report.id, item.id);
    return true;
  }

  openAnalysisExperimentReport(
    api: DashboardApi,
    experiment: {
      id: string;
      graph_id?: string | null;
      graph_revision_id?: string | null;
      graph_title?: string | null;
    },
  ): boolean {
    const existing = this.documents.find(
      (document) =>
        document.kind === "simulation-report" &&
        document.experimentId === experiment.id,
    ) as SimulationReportDocument | undefined;
    if (existing) {
      this.activateDocument(existing);
      return true;
    }

    const report = new SimulationReportDocument(
      experiment.graph_title ?? "Graph",
      experiment.graph_id ?? "",
      experiment.graph_revision_id ?? "",
    );
    this.documents.push(report);
    this.activateDocument(report);
    report.load(api, report.id, experiment.id);
    return true;
  }

  openAnalysisOptimizationReport(
    api: DashboardApi,
    plan: { id: string; strategy?: string; requested_budget?: number },
    graphInfo: {
      graph_id: string;
      graph_revision_id: string;
      graph_title: string;
    },
  ): boolean {
    const existing = this.documents.find(
      (document) =>
        document.kind === "optimization-report" &&
        document.optimizationId === plan.id,
    ) as OptimizationReportDocument | undefined;
    if (existing) {
      this.activateDocument(existing);
      return true;
    }

    const report = new OptimizationReportDocument({
      graphId: graphInfo.graph_id,
      graphRevisionId: graphInfo.graph_revision_id,
      graphTitle: graphInfo.graph_title,
      strategy: catalogOptimizationStrategy(plan.strategy),
      budget: plan.requested_budget ?? 0,
    });
    this.documents.push(report);
    this.activateDocument(report);
    report.markReady(plan.id, "", async () => false);
    report.load(api, report.id, plan.id);
    return true;
  }

  async openOptimizationResult(
    api: DashboardApi,
    graphRevisionId: string,
  ): Promise<boolean> {
    const opened = await this.openGraphRevision(api, graphRevisionId);
    if (opened) this.statusMessage = "Optimization completed.";
    return opened;
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
    correlationId?: string;
    graphTitle: string;
  }): SimulationReportDocument {
    const existing = info.correlationId
      ? (this.documents.find(
          (d) =>
            d.kind === "simulation-report" &&
            d.correlationId === info.correlationId,
        ) as SimulationReportDocument | undefined)
      : undefined;

    let report: SimulationReportDocument;
    if (existing) {
      report = existing;
      if (info.correlationId) report.markPending(info.correlationId);
    } else {
      report = new SimulationReportDocument(
        info.graphTitle,
        info.graphId,
        info.graphRevisionId,
      );
      if (info.correlationId) report.markPending(info.correlationId);
      this.documents.push(report);
    }
    this.activateDocument(report);
    return report;
  }

  createPendingOptimizationReport(info: {
    graphId: string;
    graphRevisionId: string;
    graphTitle: string;
    correlationId?: string;
    strategy: OptimizationStrategy;
    budget: number;
  }): OptimizationReportDocument {
    const existing = info.correlationId
      ? (this.documents.find(
          (document) =>
            document.kind === "optimization-report" &&
            document.correlationId === info.correlationId,
        ) as OptimizationReportDocument | undefined)
      : undefined;
    if (existing) {
      this.activateDocument(existing);
      return existing;
    }

    const report = new OptimizationReportDocument(info);
    this.documents.push(report);
    this.activateDocument(report);
    return report;
  }

  openPendingAnalysisReport(
    runId: string,
    manifest: { manifest_id: string; title: string },
  ): AnalysisReportDocument {
    const existing = this.documents.find(
      (document) =>
        document.kind === "analysis-report" && document.runId === runId,
    ) as AnalysisReportDocument | undefined;
    if (existing) {
      this.bindAnalysisReportNavigation(existing, this.api);
      this.activateDocument(existing);
      return existing;
    }

    const report = new AnalysisReportDocument(runId, manifest);
    this.bindAnalysisReportNavigation(report, this.api);
    this.documents.push(report);
    this.activateDocument(report);
    return report;
  }

  bindAnalysisReportNavigation(
    report: AnalysisReportDocument,
    api: DashboardApi | undefined,
  ): void {
    if (!api) return;
    report.openExperiment = (experiment) =>
      this.openAnalysisExperimentReport(api, experiment);
    report.openOptimization = (plan) => {
      const data = report.reportData;
      if (!data) return false;
      return this.openAnalysisOptimizationReport(api, plan, {
        graph_id: data.graph_id,
        graph_revision_id: data.source_graph_revision_id,
        graph_title: data.source_graph_title,
      });
    };
    report.openSourceGraph = async (nodeId?: string) => {
      const revisionId =
        report.reportData?.source_graph_revision_id ?? report.graphRevisionId;
      if (!revisionId) return false;
      if (!(await this.openGraphRevision(api, revisionId))) return false;
      if (!nodeId) return true;

      const graph = this.findOpenGraph(revisionId);
      if (!graph || !graph.graph.nodes.some((node) => node.id === nodeId)) {
        return false;
      }
      graph.selectNode(nodeId);
      return true;
    };
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

  markReportReadState(report: {
    id: string;
    markRead(): void;
    markUnread(): void;
  }): void {
    if (this.selectedDocumentId === report.id) report.markRead();
    else report.markUnread();
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

  private snapshotState(): DashboardWorkspaceState {
    return {
      forceParams: { ...this.forceParams },
      simulationParams: { ...this.simulationParams },
      optimizationParams: {
        ...this.optimizationParams,
        simulation_params: { ...this.optimizationParams.simulation_params },
      },
    };
  }

  private restoreState(state: DashboardWorkspaceState): void {
    Object.assign(this.forceParams, state.forceParams);
    Object.assign(this.simulationParams, state.simulationParams);
    Object.assign(this.optimizationParams, {
      ...state.optimizationParams,
      simulation_params: {
        ...state.optimizationParams.simulation_params,
      },
    });
  }

  ensureInitialFoothold(document: WorkspaceDocument | undefined): void {
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

  private findOpenGraph(
    graphRevisionId: string,
  ): EditableGraphDocument | undefined {
    return this.documents.find(
      (document) =>
        document.kind === "graph" &&
        document.loadedRevisionId === graphRevisionId,
    ) as EditableGraphDocument | undefined;
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
    dashboardRegistry[typeId]?.create?.(this);
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
    this.activateDocument(document);
    return document;
  }
}

function catalogOptimizationStrategy(
  strategy: string | null | undefined,
): OptimizationStrategy {
  switch (strategy) {
    case "null":
    case "random":
    case "simulation_informed":
    case "topology_segmentation":
    case "simulated_annealing":
    case "cvss":
      return strategy as OptimizationStrategy;
    default:
      return "cvss";
  }
}
