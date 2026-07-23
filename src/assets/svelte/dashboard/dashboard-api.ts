import type {
  OpenGraphPayload,
  OpenGraphReply,
  SaveGraphPayload,
  SaveGraphReply,
  RunSimulationPayload,
  RunSimulationReply,
  FetchSimulationReportPayload,
  FetchSimulationReportReply,
  FetchSimulationRunsPayload,
  FetchSimulationRunsReply,
} from "./contract";
import type { LoadedGraph } from "./contract";
import type { SimulationParams } from "../contracts.generated";

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
  fetchSimulationReport(
    multiStateId: string,
    graphId: string,
  ): Promise<FetchSimulationReportReply | { status: string }>;
  fetchSimulationRuns(graphIds: string[]): Promise<FetchSimulationRunsReply>;
}

/**
 * Create a typed Promise-based API facade over the LiveView connection.
 *
 * When `fetchSimulationRunsExecutor` is provided (from DashboardHost via
 * useEventReply) it is used instead of the raw pushEvent wrapper.  All other
 * methods continue to use Promise wrappers so they remain safe for concurrent
 * calls.
 */
export function createDashboardApi(
  live: LiveServer,
  fetchSimulationRunsExecutor?: (
    params: FetchSimulationRunsPayload,
  ) => Promise<FetchSimulationRunsReply>,
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
    fetchSimulationReport(multiStateId, graphId) {
      return new Promise((resolve) => {
        live.pushEvent<FetchSimulationReportPayload>(
          "fetch_simulation_report",
          { multi_state_id: multiStateId, graph_id: graphId },
          (reply) => {
            resolve(reply as FetchSimulationReportReply | { status: string });
          },
        );
      });
    },
    fetchSimulationRuns(graphIds) {
      if (fetchSimulationRunsExecutor) {
        return fetchSimulationRunsExecutor({ graph_ids: graphIds });
      }
      return new Promise((resolve) => {
        live.pushEvent<FetchSimulationRunsPayload>(
          "fetch_simulation_runs",
          { graph_ids: graphIds },
          (reply) => {
            resolve(reply as FetchSimulationRunsReply);
          },
        );
      });
    },
  };
}
