import type * as DashboardGraphContracts from "../contracts.generated/dashboard/graph";
import type * as EvaluationContracts from "../contracts.generated/dashboard/evaluation";
import type * as OptimizationContracts from "../contracts.generated/dashboard/optimization";
import type * as RunsContracts from "../contracts.generated/dashboard/runs";
import type * as SimulationContracts from "../contracts.generated/dashboard/simulation";
import type {
  FetchDocumentCatalogPayload,
  FetchDocumentCatalogReply,
} from "../contracts.generated/dashboard/workspace";
import type { GraphContract } from "../contracts.generated/graph";
import type { OptimizationParams } from "../contracts.generated/optimization";
import type { SimulationParams } from "../contracts.generated/simulation";
export type DocumentCatalogQuery = FetchDocumentCatalogPayload;

export type LiveServer = {
  pushEvent<TPayload extends object, TReply = unknown>(
    event: string,
    payload?: TPayload,
    onReply?: (reply: TReply, ref: number) => void,
  ): number;
};

export interface DashboardApi {
  openGraph(
    graphRevisionId: string,
  ): Promise<DashboardGraphContracts.OpenGraphReply>;
  saveGraph(
    graph: GraphContract,
  ): Promise<DashboardGraphContracts.SaveGraphReply>;
  runSimulation(
    graphRevisionId: string,
    correlationId: string,
    simulationParams: SimulationParams,
  ): Promise<SimulationContracts.RunSimulationReply>;
  runOptimization(
    graphRevisionId: string,
    correlationId: string,
    optimizationParams: OptimizationParams,
  ): Promise<OptimizationContracts.RunOptimizationReply>;
  requestSimulationReport(documentId: string, experimentId: string): void;
  requestOptimizationReport(documentId: string, optimizationId: string): void;
  fetchExperiments(
    graphRevisionIds: string[],
  ): Promise<SimulationContracts.FetchExperimentsReply>;
  fetchOptimizationRuns(
    graphRevisionIds: string[],
  ): Promise<OptimizationContracts.FetchOptimizationRunsReply>;
  fetchGraphConnectivity(): Promise<DashboardGraphContracts.GraphConnectivityReply>;
  fetchGraphProjection(
    graphRevisionId: string,
  ): Promise<DashboardGraphContracts.FetchGraphProjectionReply>;
  fetchDocumentCatalog(
    query: DocumentCatalogQuery,
  ): Promise<FetchDocumentCatalogReply>;
  fetchRuns(): Promise<RunsContracts.FetchRunsReply>;
  createNodeDraft(
    payload: DashboardGraphContracts.CreateNodeDraftPayload,
  ): Promise<DashboardGraphContracts.CreateNodeDraftReply>;
  createConnectionDraft(
    payload: DashboardGraphContracts.CreateConnectionDraftPayload,
  ): Promise<DashboardGraphContracts.CreateConnectionDraftReply>;
  compareGraphs(
    baseRevisionId: string,
    comparisonRevisionId: string,
  ): Promise<DashboardGraphContracts.CompareGraphsReply>;
  setGraphRevisionFavorite(
    revisionId: string,
    favorite: boolean,
  ): Promise<DashboardGraphContracts.SetGraphRevisionFavoriteReply>;
  createFolder(
    name: string,
  ): Promise<DashboardGraphContracts.CreateFolderReply>;
  deleteFolder(
    folderId: string,
  ): Promise<DashboardGraphContracts.DeleteFolderReply>;
  moveGraphToFolder(
    graphId: string,
    folderId: string | null,
  ): Promise<DashboardGraphContracts.MoveGraphToFolderReply>;
  listManifests(): Promise<EvaluationContracts.ListManifestsReply>;
  getManifest(id: string): Promise<EvaluationContracts.GetManifestReply>;
  saveManifest(
    payload: EvaluationContracts.SaveManifestPayload,
  ): Promise<EvaluationContracts.SaveManifestReply>;
  startEvaluation(
    manifestId: string,
  ): Promise<EvaluationContracts.StartEvaluationReply>;
  describeManifest(
    content: Record<string, unknown>,
  ): Promise<EvaluationContracts.DescribeManifestReply>;
  requestEvaluationReport(documentId: string, runId: string): void;
  requestEvaluationAnalysis(
    payload: EvaluationContracts.RequestEvaluationAnalysisPayload,
  ): Promise<EvaluationContracts.RequestEvaluationAnalysisReply>;
  cancelRun(
    payload: RunsContracts.CancelRunPayload,
  ): Promise<RunsContracts.CancelRunReply>;
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
      return requestReply<
        DashboardGraphContracts.OpenGraphPayload,
        DashboardGraphContracts.OpenGraphReply
      >(live, "open_graph", { graph_revision_id: graphRevisionId });
    },
    saveGraph(graph) {
      if (graph.revision_id == null) {
        return Promise.resolve({ status: "invalid_graph", errors: [] });
      }

      return requestReply<
        DashboardGraphContracts.SaveGraphPayload,
        DashboardGraphContracts.SaveGraphReply
      >(live, "save_graph", {
        graph: {
          id: graph.id,
          revision_id: graph.revision_id,
          title: graph.title,
          nodes: graph.nodes,
          edges: graph.edges,
        },
      });
    },
    runSimulation(graphRevisionId, correlationId, simulationParams) {
      return requestReply<
        SimulationContracts.RunSimulationPayload,
        SimulationContracts.RunSimulationReply
      >(live, "run_simulation_request", {
        request: {
          graph_revision_id: graphRevisionId,
          correlation_id: correlationId,
          simulation_params: simulationParams,
        },
      });
    },
    runOptimization(graphRevisionId, correlationId, optimizationParams) {
      return requestReply<
        OptimizationContracts.RunOptimizationPayload,
        OptimizationContracts.RunOptimizationReply
      >(live, "run_optimization_request", {
        request: {
          graph_revision_id: graphRevisionId,
          correlation_id: correlationId,
          optimization_params: optimizationParams,
        },
      });
    },
    requestSimulationReport(documentId, experimentId) {
      live.pushEvent<SimulationContracts.FetchSimulationReportPayload>(
        "fetch_simulation_report",
        {
          document_id: documentId,
          experiment_id: experimentId,
        },
      );
    },
    requestOptimizationReport(documentId, optimizationId) {
      live.pushEvent<OptimizationContracts.FetchOptimizationReportPayload>(
        "fetch_optimization_report",
        {
          document_id: documentId,
          optimization_id: optimizationId,
        },
      );
    },
    fetchExperiments(graphRevisionIds) {
      return requestReply<
        SimulationContracts.FetchExperimentsPayload,
        SimulationContracts.FetchExperimentsReply
      >(live, "fetch_experiments", { graph_revision_ids: graphRevisionIds });
    },
    fetchOptimizationRuns(graphRevisionIds) {
      return requestReply<
        OptimizationContracts.FetchOptimizationRunsPayload,
        OptimizationContracts.FetchOptimizationRunsReply
      >(live, "fetch_optimization_runs", {
        graph_revision_ids: graphRevisionIds,
      });
    },
    fetchGraphConnectivity() {
      return requestReply<{}, DashboardGraphContracts.GraphConnectivityReply>(
        live,
        "fetch_graph_connectivity",
        {},
      );
    },
    fetchGraphProjection(graphRevisionId) {
      return requestReply<
        DashboardGraphContracts.FetchGraphProjectionPayload,
        DashboardGraphContracts.FetchGraphProjectionReply
      >(live, "fetch_graph_projection", { graph_revision_id: graphRevisionId });
    },
    fetchDocumentCatalog(query) {
      return requestReply<
        FetchDocumentCatalogPayload,
        FetchDocumentCatalogReply
      >(live, "fetch_document_catalog", query);
    },
    fetchRuns() {
      return requestReply<
        RunsContracts.FetchRunsPayload,
        RunsContracts.FetchRunsReply
      >(live, "fetch_runs", {});
    },
    createNodeDraft(payload) {
      return requestReply<
        DashboardGraphContracts.CreateNodeDraftPayload,
        DashboardGraphContracts.CreateNodeDraftReply
      >(live, "create_node_draft", payload);
    },
    createConnectionDraft(payload) {
      return requestReply<
        DashboardGraphContracts.CreateConnectionDraftPayload,
        DashboardGraphContracts.CreateConnectionDraftReply
      >(live, "create_connection_draft", payload);
    },
    compareGraphs(baseRevisionId, comparisonRevisionId) {
      return requestReply<
        DashboardGraphContracts.CompareGraphsPayload,
        DashboardGraphContracts.CompareGraphsReply
      >(live, "compare_graphs", {
        base_revision_id: baseRevisionId,
        comparison_revision_id: comparisonRevisionId,
      });
    },
    setGraphRevisionFavorite(revisionId, favorite) {
      return requestReply<
        DashboardGraphContracts.SetGraphRevisionFavoritePayload,
        DashboardGraphContracts.SetGraphRevisionFavoriteReply
      >(live, "set_graph_revision_favorite", {
        graph_revision_id: revisionId,
        favorite,
      });
    },
    createFolder(name) {
      return requestReply<
        DashboardGraphContracts.CreateFolderPayload,
        DashboardGraphContracts.CreateFolderReply
      >(live, "create_folder", { name });
    },
    deleteFolder(folderId) {
      return requestReply<
        DashboardGraphContracts.DeleteFolderPayload,
        DashboardGraphContracts.DeleteFolderReply
      >(live, "delete_folder", { folder_id: folderId });
    },
    moveGraphToFolder(graphId, folderId) {
      return requestReply<
        DashboardGraphContracts.MoveGraphToFolderPayload,
        DashboardGraphContracts.MoveGraphToFolderReply
      >(live, "move_graph_to_folder", {
        graph_id: graphId,
        folder_id: folderId,
      });
    },
    listManifests() {
      return requestReply<
        EvaluationContracts.ListManifestsPayload,
        EvaluationContracts.ListManifestsReply
      >(live, "list_manifests", {});
    },
    getManifest(id) {
      return requestReply<
        EvaluationContracts.GetManifestPayload,
        EvaluationContracts.GetManifestReply
      >(live, "get_manifest", { id });
    },
    saveManifest(payload) {
      return requestReply<
        EvaluationContracts.SaveManifestPayload,
        EvaluationContracts.SaveManifestReply
      >(live, "save_manifest", payload);
    },
    startEvaluation(manifestId) {
      return requestReply<
        EvaluationContracts.StartEvaluationPayload,
        EvaluationContracts.StartEvaluationReply
      >(live, "start_evaluation", { manifest_id: manifestId });
    },
    describeManifest(content) {
      return requestReply<
        EvaluationContracts.DescribeManifestPayload,
        EvaluationContracts.DescribeManifestReply
      >(live, "describe_manifest", { content });
    },
    requestEvaluationReport(documentId, runId) {
      live.pushEvent<EvaluationContracts.FetchEvaluationReportPayload>(
        "fetch_evaluation_report",
        {
          document_id: documentId,
          run_id: runId,
        },
      );
    },
    requestEvaluationAnalysis(payload) {
      return requestReply<
        EvaluationContracts.RequestEvaluationAnalysisPayload,
        EvaluationContracts.RequestEvaluationAnalysisReply
      >(live, "request_evaluation_analysis", payload);
    },
    cancelRun(payload) {
      return requestReply<
        RunsContracts.CancelRunPayload,
        RunsContracts.CancelRunReply
      >(live, "cancel_run", payload);
    },
  };
}
