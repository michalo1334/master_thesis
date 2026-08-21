import type {
  OpenGraphPayload,
  OpenGraphReply,
  SaveGraphPayload,
  SaveGraphReply,
  RunSimulationPayload,
  RunSimulationReply,
  FetchSimulationReportPayload,
  FetchOptimizationReportPayload,
  FetchExperimentsPayload,
  FetchExperimentsReply,
  FetchOptimizationRunsPayload,
  FetchOptimizationRunsReply,
  OptimizationParams,
  RunOptimizationPayload,
  RunOptimizationReply,
  SimulationParams,
  GraphConnectivityReply,
  CreateNodeDraftPayload,
  CreateNodeDraftReply,
  CreateConnectionDraftPayload,
  CreateConnectionDraftReply,
  CompareGraphsPayload,
  CompareGraphsReply,
  SetGraphRevisionFavoritePayload,
  SetGraphRevisionFavoriteReply,
  CreateFolderPayload,
  CreateFolderReply,
  DeleteFolderPayload,
  DeleteFolderReply,
  MoveGraphToFolderPayload,
  MoveGraphToFolderReply,
  FetchGraphProjectionPayload,
  FetchGraphProjectionReply,
  FetchDocumentCatalogPayload,
  FetchDocumentCatalogReply,
  GetManifestPayload,
  GetManifestReply,
  ListManifestsPayload,
  ListManifestsReply,
  SaveManifestPayload,
  SaveManifestReply,
  StartEvaluationPayload,
  StartEvaluationReply,
  FetchEvaluationReportPayload,
} from "./contract";
import type { LoadedGraph } from "./contract";
import type { FetchRunsPayload, FetchRunsReply } from "../contracts.generated";

export type DocumentCatalogQuery = FetchDocumentCatalogPayload;

export type LiveServer = {
  pushEvent<TPayload extends object, TReply = unknown>(
    event: string,
    payload?: TPayload,
    onReply?: (reply: TReply, ref: number) => void,
  ): number;
};

export interface DashboardApi {
  openGraph(graphRevisionId: string): Promise<OpenGraphReply>;
  saveGraph(graph: LoadedGraph): Promise<SaveGraphReply>;
  runSimulation(
    graphRevisionId: string,
    correlationId: string,
    simulationParams: SimulationParams,
  ): Promise<RunSimulationReply>;
  runOptimization(
    graphRevisionId: string,
    correlationId: string,
    optimizationParams: OptimizationParams,
  ): Promise<RunOptimizationReply>;
  requestSimulationReport(documentId: string, experimentId: string): void;
  requestOptimizationReport(documentId: string, optimizationId: string): void;
  fetchExperiments(graphRevisionIds: string[]): Promise<FetchExperimentsReply>;
  fetchOptimizationRuns(
    graphRevisionIds: string[],
  ): Promise<FetchOptimizationRunsReply>;
  fetchGraphConnectivity(): Promise<GraphConnectivityReply>;
  fetchGraphProjection(
    graphRevisionId: string,
  ): Promise<FetchGraphProjectionReply>;
  fetchDocumentCatalog(
    query: DocumentCatalogQuery,
  ): Promise<FetchDocumentCatalogReply>;
  fetchRuns(): Promise<FetchRunsReply>;
  createNodeDraft(
    payload: CreateNodeDraftPayload,
  ): Promise<CreateNodeDraftReply>;
  createConnectionDraft(
    payload: CreateConnectionDraftPayload,
  ): Promise<CreateConnectionDraftReply>;
  compareGraphs(
    baseRevisionId: string,
    comparisonRevisionId: string,
  ): Promise<CompareGraphsReply>;
  setGraphRevisionFavorite(
    revisionId: string,
    favorite: boolean,
  ): Promise<SetGraphRevisionFavoriteReply>;
  createFolder(name: string): Promise<CreateFolderReply>;
  deleteFolder(folderId: string): Promise<DeleteFolderReply>;
  moveGraphToFolder(
    graphId: string,
    folderId: string | null,
  ): Promise<MoveGraphToFolderReply>;
  listManifests(): Promise<ListManifestsReply>;
  getManifest(id: string): Promise<GetManifestReply>;
  saveManifest(payload: SaveManifestPayload): Promise<SaveManifestReply>;
  startEvaluation(manifestId: string): Promise<StartEvaluationReply>;
  requestEvaluationReport(documentId: string, runId: string): void;
}

function requestReply<TPayload extends object, TReply>(
  live: LiveServer,
  event: string,
  payload: TPayload,
): Promise<TReply> {
  return new Promise((resolve) => {
    live.pushEvent<TPayload, TReply>(event, payload, resolve);
  });
}

export function createDashboardApi(live: LiveServer): DashboardApi {
  return {
    openGraph(graphRevisionId) {
      return requestReply<OpenGraphPayload, OpenGraphReply>(
        live,
        "open_graph",
        { graph_revision_id: graphRevisionId },
      );
    },
    saveGraph(graph) {
      if (graph.revision_id == null) {
        return Promise.resolve({ status: "invalid_graph" });
      }

      return requestReply<SaveGraphPayload, SaveGraphReply>(
        live,
        "save_graph",
        {
          graph: {
            id: graph.id,
            revision_id: graph.revision_id,
            title: graph.title,
            nodes: graph.nodes,
            edges: graph.edges,
          },
        },
      );
    },
    runSimulation(graphRevisionId, correlationId, simulationParams) {
      return requestReply<RunSimulationPayload, RunSimulationReply>(
        live,
        "run_simulation_request",
        {
          request: {
            graph_revision_id: graphRevisionId,
            correlation_id: correlationId,
            simulation_params: simulationParams,
          },
        },
      );
    },
    runOptimization(graphRevisionId, correlationId, optimizationParams) {
      return requestReply<RunOptimizationPayload, RunOptimizationReply>(
        live,
        "run_optimization_request",
        {
          request: {
            graph_revision_id: graphRevisionId,
            correlation_id: correlationId,
            optimization_params: optimizationParams,
          },
        },
      );
    },
    requestSimulationReport(documentId, experimentId) {
      live.pushEvent<FetchSimulationReportPayload>("fetch_simulation_report", {
        document_id: documentId,
        experiment_id: experimentId,
      });
    },
    requestOptimizationReport(documentId, optimizationId) {
      live.pushEvent<FetchOptimizationReportPayload>(
        "fetch_optimization_report",
        {
          document_id: documentId,
          optimization_id: optimizationId,
        },
      );
    },
    fetchExperiments(graphRevisionIds) {
      return requestReply<FetchExperimentsPayload, FetchExperimentsReply>(
        live,
        "fetch_experiments",
        { graph_revision_ids: graphRevisionIds },
      );
    },
    fetchOptimizationRuns(graphRevisionIds) {
      return requestReply<
        FetchOptimizationRunsPayload,
        FetchOptimizationRunsReply
      >(live, "fetch_optimization_runs", {
        graph_revision_ids: graphRevisionIds,
      });
    },
    fetchGraphConnectivity() {
      return requestReply<{}, GraphConnectivityReply>(
        live,
        "fetch_graph_connectivity",
        {},
      );
    },
    fetchGraphProjection(graphRevisionId) {
      return requestReply<
        FetchGraphProjectionPayload,
        FetchGraphProjectionReply
      >(live, "fetch_graph_projection", { graph_revision_id: graphRevisionId });
    },
    fetchDocumentCatalog(query) {
      return requestReply<
        FetchDocumentCatalogPayload,
        FetchDocumentCatalogReply
      >(live, "fetch_document_catalog", query);
    },
    fetchRuns() {
      return requestReply<FetchRunsPayload, FetchRunsReply>(
        live,
        "fetch_runs",
        {},
      );
    },
    createNodeDraft(payload) {
      return requestReply<CreateNodeDraftPayload, CreateNodeDraftReply>(
        live,
        "create_node_draft",
        payload,
      );
    },
    createConnectionDraft(payload) {
      return requestReply<
        CreateConnectionDraftPayload,
        CreateConnectionDraftReply
      >(live, "create_connection_draft", payload);
    },
    compareGraphs(baseRevisionId, comparisonRevisionId) {
      return requestReply<CompareGraphsPayload, CompareGraphsReply>(
        live,
        "compare_graphs",
        {
          base_revision_id: baseRevisionId,
          comparison_revision_id: comparisonRevisionId,
        },
      );
    },
    setGraphRevisionFavorite(revisionId, favorite) {
      return requestReply<
        SetGraphRevisionFavoritePayload,
        SetGraphRevisionFavoriteReply
      >(live, "set_graph_revision_favorite", {
        graph_revision_id: revisionId,
        favorite,
      });
    },
    createFolder(name) {
      return requestReply<CreateFolderPayload, CreateFolderReply>(
        live,
        "create_folder",
        { name },
      );
    },
    deleteFolder(folderId) {
      return requestReply<DeleteFolderPayload, DeleteFolderReply>(
        live,
        "delete_folder",
        { folder_id: folderId },
      );
    },
    moveGraphToFolder(graphId, folderId) {
      return requestReply<MoveGraphToFolderPayload, MoveGraphToFolderReply>(
        live,
        "move_graph_to_folder",
        { graph_id: graphId, folder_id: folderId },
      );
    },
    listManifests() {
      return requestReply<ListManifestsPayload, ListManifestsReply>(
        live,
        "list_manifests",
        {},
      );
    },
    getManifest(id) {
      return requestReply<GetManifestPayload, GetManifestReply>(
        live,
        "get_manifest",
        { id },
      );
    },
    saveManifest(payload) {
      return requestReply<SaveManifestPayload, SaveManifestReply>(
        live,
        "save_manifest",
        payload,
      );
    },
    startEvaluation(manifestId) {
      return requestReply<StartEvaluationPayload, StartEvaluationReply>(
        live,
        "start_evaluation",
        { manifest_id: manifestId },
      );
    },
    requestEvaluationReport(documentId, runId) {
      live.pushEvent<FetchEvaluationReportPayload>("fetch_evaluation_report", {
        document_id: documentId,
        run_id: runId,
      });
    },
  };
}
