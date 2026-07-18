import type { Live } from "live_svelte";
import {
  type Id,
  type Graph,
  type RequestCorrelationId,
  type OpenGraphPayload,
  type SaveGraphPayload,
} from "./contract";

interface DashboardServer {
  openGraph(graphId: Id): RequestCorrelationId;
  saveGraph(graph: Graph): RequestCorrelationId;
}

export type LiveServer = {
  pushEvent<TPayload extends object>(
    event: string,
    payload?: TPayload,
    onReply?: (reply: unknown, ref: number) => void,
  ): RequestCorrelationId;
};

export function createDashboardServer(live: LiveServer): DashboardServer {
  return {
    openGraph(graphId) {
      return live.pushEvent<OpenGraphPayload>("open_graph", {
        graph_id: graphId,
      });
    },
    saveGraph(graph) {
      return live.pushEvent<SaveGraphPayload>("save_graph", { graph: graph });
    },
  };
}
