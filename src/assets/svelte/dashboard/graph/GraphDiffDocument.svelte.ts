import { SvelteMap } from "svelte/reactivity";
import type {
  GraphDiffCounts,
  GraphDiffResult,
  GraphDiffStatusEntry,
  LoadedGraph,
} from "../contract";
import { WorkspaceDocumentBase } from "../workspace/WorkspaceDocument.svelte";
import type { DashboardRecoveryContext } from "../workspace/recovery-context";
import {
  isPersistedDocumentOfKind,
  type PersistedWorkspaceDocument,
} from "../../ui-kit/workspace/workspace-persistence";

export type GraphDiffStatus = GraphDiffStatusEntry["status"];

export class GraphDiffDocument extends WorkspaceDocumentBase {
  readonly kind = "graph-diff" as const;
  readonly documentLabel = "Comparison";
  readonly icon = "graph-diff" as const satisfies string;
  readonly id = crypto.randomUUID();
  baseRevisionId = $state("");
  comparisonRevisionId = $state("");
  baseTitle = $state("");
  comparisonTitle = $state("");
  title = $state("");
  graph = $state.raw<LoadedGraph>({ id: "", title: "", nodes: [], edges: [] });
  nodeStatusById = $state.raw<ReadonlyMap<string, GraphDiffStatus>>(
    new SvelteMap(),
  );
  edgeStatusById = $state.raw<ReadonlyMap<string, GraphDiffStatus>>(
    new SvelteMap(),
  );
  nodeCounts = $state<GraphDiffCounts>({ added: 0, removed: 0, unchanged: 0 });
  edgeCounts = $state<GraphDiffCounts>({ added: 0, removed: 0, unchanged: 0 });
  status = $state<"ready" | "loading" | "loaded" | "error">("loaded");

  constructor(
    base: LoadedGraph,
    comparison: { revisionId: string; title: string },
    result: GraphDiffResult,
  ) {
    super();
    this.replace(base, comparison, result);
  }

  static fromPersisted(
    data: unknown,
    _context: DashboardRecoveryContext,
  ): GraphDiffDocument | undefined {
    if (!isGraphDiffPersisted(data)) return undefined;
    const graph: LoadedGraph = {
      id: "",
      title: data.title,
      revision_id: data.ids.baseRevisionId,
      nodes: [],
      edges: [],
    };
    const document = new GraphDiffDocument(
      graph,
      {
        revisionId: data.ids.comparisonRevisionId,
        title: data.title,
      },
      {
        graph,
        node_status: [],
        edge_status: [],
        node_counts: { added: 0, removed: 0, unchanged: 0 },
        edge_counts: { added: 0, removed: 0, unchanged: 0 },
      },
    );
    document.title = data.title;
    document.status = "ready";
    document.setPersisted(data);
    return document;
  }

  toPersisted(): PersistedWorkspaceDocument | undefined {
    return {
      kind: "graph-diff",
      ids: {
        baseRevisionId: this.baseRevisionId,
        comparisonRevisionId: this.comparisonRevisionId,
      },
      title: this.title,
    };
  }

  needsRecovery(): boolean {
    return this.status === "ready" && this.persistedData !== undefined;
  }

  recover(context: DashboardRecoveryContext): void {
    const persisted = this.persistedData as PersistedGraphDiff | undefined;
    if (!persisted) return;
    this.status = "loading";
    void (async () => {
      try {
        const [baseReply, comparisonReply, comparison] = await Promise.all([
          context.api.openGraph(persisted.ids.baseRevisionId),
          context.api.openGraph(persisted.ids.comparisonRevisionId),
          context.api.compareGraphs(
            persisted.ids.baseRevisionId,
            persisted.ids.comparisonRevisionId,
          ),
        ]);
        if (
          baseReply.status !== "ok" ||
          !baseReply.graph ||
          comparisonReply.status !== "ok" ||
          !comparisonReply.graph ||
          comparison.status !== "ok" ||
          !comparison.result
        ) {
          this.status = "error";
          return;
        }
        this.replace(
          baseReply.graph,
          {
            revisionId: persisted.ids.comparisonRevisionId,
            title: comparisonReply.graph.title,
          },
          comparison.result,
        );
      } catch {
        this.status = "error";
      }
    })();
  }

  replace(
    base: LoadedGraph,
    comparison: { revisionId: string; title: string },
    result: GraphDiffResult,
  ): void {
    this.baseRevisionId = base.revision_id ?? "";
    this.comparisonRevisionId = comparison.revisionId;
    this.baseTitle = base.title;
    this.comparisonTitle = comparison.title;
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
    this.status = "loaded";
  }
}

type PersistedGraphDiff = PersistedWorkspaceDocument & {
  ids: { baseRevisionId: string; comparisonRevisionId: string };
};

function isGraphDiffPersisted(value: unknown): value is PersistedGraphDiff {
  return isPersistedDocumentOfKind<PersistedGraphDiff["ids"]>(
    value,
    "graph-diff",
    ["baseRevisionId", "comparisonRevisionId"],
  );
}
