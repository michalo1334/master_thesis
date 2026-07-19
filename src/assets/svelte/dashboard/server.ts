import {
  type Id,
  type LoadedGraph,
  type RequestCorrelationId,
  type OpenGraphPayload,
  type OpenGraphReply,
  type SaveGraphPayload,
  type SaveGraphReply,
} from "./contract";

export interface DashboardServer {
  openGraph(
    graphId: Id,
    onReply: (reply: OpenGraphReply) => void,
  ): RequestCorrelationId;
  saveGraph(
    graph: LoadedGraph,
    onReply: (reply: SaveGraphReply) => void,
  ): RequestCorrelationId;
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
  };
}
