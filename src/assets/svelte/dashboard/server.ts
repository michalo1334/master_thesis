import {
  type Id,
  type LoadedGraph,
  type RequestCorrelationId,
  type OpenGraphPayload,
  type OpenGraphReply,
  type SaveGraphPayload,
  type SaveGraphReply,
  type FetchSimulationReportPayload,
  type FetchSimulationReportReply,
  type FetchSimulationRunsPayload,
  type FetchSimulationRunsReply,
} from "./contract";
import { useLiveEvent } from "live_svelte";
import type { DashboardController } from "./DashboardController.svelte";
export interface DashboardServer {
  openGraph(
    graphId: Id,
    onReply: (reply: OpenGraphReply) => void,
  ): RequestCorrelationId;
  saveGraph(
    graph: LoadedGraph,
    onReply: (reply: SaveGraphReply) => void,
  ): RequestCorrelationId;
  runSimulation(graphId: string): RequestCorrelationId;
  fetchSimulationReport(
    multiStateId: string,
    graphId: string,
    onReply: (reply: FetchSimulationReportReply) => void,
  ): RequestCorrelationId;
  fetchSimulationRuns(
    graphIds: string[],
    onReply: (reply: FetchSimulationRunsReply) => void,
  ): RequestCorrelationId;
}
export type LiveServer = {
  pushEvent<TPayload extends object>(
    event: string,
    payload?: TPayload,
    onReply?: (reply: unknown, ref: number) => void,
  ): RequestCorrelationId;
};

export function registerSimulationDoneHandler(handler: (payload: any) => void) {
  useLiveEvent("simulation_done", handler);
}

export function createDashboardServer(live: LiveServer): DashboardServer {
  return {
    openGraph(graphId, onReply) {
      return live.pushEvent<OpenGraphPayload>(
        "open_graph",
        { graph_id: graphId },
        (reply) => {
          onReply(reply as OpenGraphReply);
        },
      );
    },
    saveGraph(graph, onReply) {
      return live.pushEvent<SaveGraphPayload>(
        "save_graph",
        { graph },
        (reply) => {
          onReply(reply as SaveGraphReply);
        },
      );
    },
    runSimulation(graphId) {
      return live.pushEvent<{ graph_id: string }>("run_simulation", {
        graph_id: graphId,
      });
    },
    fetchSimulationReport(multiStateId, graphId, onReply) {
      return live.pushEvent<FetchSimulationReportPayload>(
        "fetch_simulation_report",
        { multi_state_id: multiStateId, graph_id: graphId },
        (reply) => {
          onReply(reply as FetchSimulationReportReply);
        },
      );
    },
    fetchSimulationRuns(graphIds, onReply) {
      return live.pushEvent<FetchSimulationRunsPayload>(
        "fetch_simulation_runs",
        { graph_ids: graphIds },
        (reply) => {
          onReply(reply as FetchSimulationRunsReply);
        },
      );
    },
  };
}
