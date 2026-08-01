import type {
  OpenGraphPayload,
  OpenGraphReply,
  SaveGraphPayload,
  SaveGraphReply,
  RunSimulationPayload,
  RunSimulationReply,
  FetchSimulationReportPayload,
  FetchExperimentsPayload,
  FetchExperimentsReply,
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
} from "./contract";
import type { LoadedGraph } from "./contract";

export type LiveServer = {
  pushEvent<TPayload extends object, TReply = unknown>(
    event: string,
    payload?: TPayload,
    onReply?: (reply: TReply, ref: number) => void,
  ): number;
};

export interface DashboardApi {
  openGraph(graphId: string): Promise<OpenGraphReply>;
  saveGraph(graph: LoadedGraph): Promise<SaveGraphReply>;
  runSimulation(
    graphId: string,
    correlationId: string,
    simulationParams: SimulationParams,
  ): Promise<RunSimulationReply>;
  runOptimization(
    graphId: string,
    correlationId: string,
    optimizationParams: OptimizationParams,
  ): Promise<RunOptimizationReply>;
  requestSimulationReport(experimentId: string, graphId: string): void;
  fetchExperiments(graphIds: string[]): Promise<FetchExperimentsReply>;
  fetchGraphConnectivity(): Promise<GraphConnectivityReply>;
  createNodeDraft(
    payload: CreateNodeDraftPayload,
  ): Promise<CreateNodeDraftReply>;
  createConnectionDraft(
    payload: CreateConnectionDraftPayload,
  ): Promise<CreateConnectionDraftReply>;
  compareGraphs(
    baseGraph: LoadedGraph,
    comparisonGraphId: string,
  ): Promise<CompareGraphsReply>;
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
    openGraph(graphId) {
      return requestReply<OpenGraphPayload, OpenGraphReply>(
        live,
        "open_graph",
        { graph_id: graphId },
      );
    },
    saveGraph(graph) {
      return requestReply<SaveGraphPayload, SaveGraphReply>(
        live,
        "save_graph",
        { graph },
      );
    },
    runSimulation(graphId, correlationId, simulationParams) {
      return requestReply<RunSimulationPayload, RunSimulationReply>(
        live,
        "run_simulation_request",
        {
          request: {
            graph_id: graphId,
            correlation_id: correlationId,
            simulation_params: simulationParams,
          },
        },
      );
    },
    runOptimization(graphId, correlationId, optimizationParams) {
      return requestReply<RunOptimizationPayload, RunOptimizationReply>(
        live,
        "run_optimization_request",
        {
          request: {
            graph_id: graphId,
            correlation_id: correlationId,
            optimization_params: optimizationParams,
          },
        },
      );
    },
    requestSimulationReport(experimentId, graphId) {
      live.pushEvent<FetchSimulationReportPayload>("fetch_simulation_report", {
        experiment_id: experimentId,
        graph_id: graphId,
      });
    },
    fetchExperiments(graphIds) {
      return requestReply<FetchExperimentsPayload, FetchExperimentsReply>(
        live,
        "fetch_experiments",
        { graph_ids: graphIds },
      );
    },
    fetchGraphConnectivity() {
      return requestReply<{}, GraphConnectivityReply>(
        live,
        "fetch_graph_connectivity",
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
    compareGraphs(baseGraph, comparisonGraphId) {
      return requestReply<CompareGraphsPayload, CompareGraphsReply>(
        live,
        "compare_graphs",
        { base_graph: baseGraph, comparison_graph_id: comparisonGraphId },
      );
    },
  };
}
