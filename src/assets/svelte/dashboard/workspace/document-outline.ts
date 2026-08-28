import type { GraphSummary } from "../../contracts.generated/dashboard/graph";
import {
  isGraphDiff,
  isReport,
  type WorkspaceDocument,
} from "./WorkspaceDocument.svelte";

export function folderIdForGraphId(
  graphId: string,
  graphSummaries: readonly GraphSummary[],
): string | null | undefined {
  return graphSummaries.find((summary) => summary.graph_id === graphId)
    ?.folder_id;
}

export function hasAnalysisMetadata(
  document: WorkspaceDocument,
): document is Extract<
  WorkspaceDocument,
  { kind: "simulation-report" | "optimization-report" | "comparison-report" }
> {
  return (
    isReport(document) &&
    document.kind !== "analysis-report" &&
    !!(document.analysisId || document.analysisTitle)
  );
}

export function folderIdForDocument(
  document: WorkspaceDocument,
  graphSummaries: readonly GraphSummary[],
): string | null | undefined {
  if (document.kind === "graph") {
    const graphId = document.graph.id;
    return graphId ? folderIdForGraphId(graphId, graphSummaries) : undefined;
  }

  if (isReport(document)) {
    return document.graphId
      ? folderIdForGraphId(document.graphId, graphSummaries)
      : undefined;
  }

  if (document.kind === "graph-diff") {
    const graphId = graphSummaries.find(
      (summary) => summary.revision_id === document.baseRevisionId,
    )?.graph_id;
    return graphId ? folderIdForGraphId(graphId, graphSummaries) : undefined;
  }

  return undefined;
}

export function parentDocument(
  document: WorkspaceDocument,
  graphsByRevisionId: ReadonlyMap<string, WorkspaceDocument>,
): WorkspaceDocument | undefined {
  if (isReport(document)) {
    return graphsByRevisionId.get(document.graphRevisionId);
  }

  if (isGraphDiff(document)) {
    return graphsByRevisionId.get(document.baseRevisionId);
  }

  if (document.kind !== "graph") return undefined;

  if (!document.loadedRevisionId || !document.graph.parent_revision_id)
    return undefined;

  const parent = graphsByRevisionId.get(document.graph.parent_revision_id);
  if (!parent || parent.id === document.id) return undefined;

  // A malformed parent chain is shown at the root instead of recursing forever.
  const visited = new Set([document.id]);
  let current: WorkspaceDocument | undefined = parent;
  while (current) {
    if (visited.has(current.id)) return undefined;
    visited.add(current.id);
    current =
      current.kind === "graph" && current.graph.parent_revision_id
        ? graphsByRevisionId.get(current.graph.parent_revision_id)
        : undefined;
  }

  return parent;
}

export function graphIdForDocument(
  document: WorkspaceDocument,
): string | undefined {
  return document.kind === "graph" && document.loadedRevisionId
    ? document.graph.id
    : undefined;
}
