import { SvelteMap } from "svelte/reactivity";
import type {
  GraphDiffCounts,
  GraphDiffResult,
  GraphDiffStatusEntry,
  GraphSummary,
  LoadedGraph,
} from "../contract";

export type GraphDiffStatus = GraphDiffStatusEntry["status"];

export class GraphDiffDocument {
  readonly kind = "graph-diff" as const;
  readonly id = crypto.randomUUID();
  readonly baseGraphId: string;
  readonly comparisonGraphId: string;
  readonly title: string;
  readonly graph: LoadedGraph;
  readonly nodeStatusById: ReadonlyMap<string, GraphDiffStatus>;
  readonly edgeStatusById: ReadonlyMap<string, GraphDiffStatus>;
  readonly nodeCounts: GraphDiffCounts;
  readonly edgeCounts: GraphDiffCounts;

  constructor(
    base: LoadedGraph,
    comparison: GraphSummary,
    result: GraphDiffResult,
  ) {
    this.baseGraphId = base.id;
    this.comparisonGraphId = comparison.id;
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
