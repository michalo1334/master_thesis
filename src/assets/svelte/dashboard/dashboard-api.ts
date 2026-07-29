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
  RunOptimizationReply,
  SimulationParams,
} from "./contract";
import type { LoadedGraph } from "./contract";

export type LiveServer = {
  pushEvent<TPayload extends object>(
    event: string,
    payload?: TPayload,
    onReply?: (reply: unknown, ref: number) => void,
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
}

/**
 * Create a typed Promise-based API facade over the LiveView connection.
 *
 * When `fetchExperimentsExecutor` is provided (from DashboardHost via
 * useEventReply) it is used instead of the raw pushEvent wrapper.  All other
 * methods continue to use Promise wrappers so they remain safe for concurrent
 * calls.
 */
export function createDashboardApi(
  live: LiveServer,
  fetchExperimentsExecutor?: (
    params: FetchExperimentsPayload,
  ) => Promise<FetchExperimentsReply>,
): DashboardApi {
  return {
    openGraph(graphId) {
      return new Promise((resolve) => {
        live.pushEvent<OpenGraphPayload>(
          "open_graph",
          { graph_id: graphId },
          (reply) => {
            resolve(reply as OpenGraphReply);
          },
        );
      });
    },
    saveGraph(graph) {
      return new Promise((resolve) => {
        live.pushEvent<SaveGraphPayload>("save_graph", { graph }, (reply) => {
          resolve(reply as SaveGraphReply);
        });
      });
    },
    runSimulation(graphId, correlationId, simulationParams) {
      return new Promise((resolve) => {
        live.pushEvent<RunSimulationPayload>(
          "run_simulation_request",
          {
            request: {
              graph_id: graphId,
              correlation_id: correlationId,
              simulation_params: simulationParams,
            },
          },
          (reply) => {
            resolve(reply as RunSimulationReply);
          },
        );
      });
    },
    runOptimization(graphId, correlationId, optimizationParams) {
      return new Promise((resolve) => {
        live.pushEvent(
          "run_optimization_request",
          {
            request: {
              graph_id: graphId,
              correlation_id: correlationId,
              optimization_params: optimizationParams,
            },
          },
          (reply) => {
            resolve(reply as RunOptimizationReply);
          },
        );
      });
    },
    requestSimulationReport(experimentId, graphId) {
      live.pushEvent<FetchSimulationReportPayload>("fetch_simulation_report", {
        experiment_id: experimentId,
        graph_id: graphId,
      });
    },
    fetchExperiments(graphIds) {
      if (fetchExperimentsExecutor) {
        return fetchExperimentsExecutor({ graph_ids: graphIds });
      }
      return new Promise((resolve) => {
        live.pushEvent<FetchExperimentsPayload>(
          "fetch_experiments",
          { graph_ids: graphIds },
          (reply) => {
            resolve(reply as FetchExperimentsReply);
          },
        );
      });
    },
  };
}
