import { SvelteMap } from "svelte/reactivity";
import type {
  GraphDiffCounts,
  GraphDiffResult,
  GraphDiffStatusEntry,
  LoadedGraph,
} from "../contract";
import type { IconName } from "../types";

export type GraphDiffStatus = GraphDiffStatusEntry["status"];

export class GraphDiffDocument {
  readonly kind = "graph-diff" as const;
  readonly icon = "graph-diff" as const satisfies IconName;
  readonly id = crypto.randomUUID();
  readonly baseRevisionId: string;
  readonly comparisonRevisionId: string;
  readonly title: string;
  readonly graph: LoadedGraph;
  readonly nodeStatusById: ReadonlyMap<string, GraphDiffStatus>;
  readonly edgeStatusById: ReadonlyMap<string, GraphDiffStatus>;
  readonly nodeCounts: GraphDiffCounts;
  readonly edgeCounts: GraphDiffCounts;

  constructor(
    base: LoadedGraph,
    comparison: { revisionId: string; title: string },
    result: GraphDiffResult,
  ) {
    this.baseRevisionId = base.revision_id ?? "";
    this.comparisonRevisionId = comparison.revisionId;
    this.title = `${base.title} compared with ${comparison.title}`;
    this.graph = result.graph;
    this.nodeStatusById = new SvelteMap(
      result.node_status.map(({ id, status }) => [id, status]),
    );
    this.edgeStatusById = new SvelteMap(
      result.edge_status.map(({ id, status }) => [id, status]),
    );
    this.nodeCounts = result.node_counts;
    this.edgeCounts = result.edge_counts;
  }
}
