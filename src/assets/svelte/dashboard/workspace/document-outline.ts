import type { FolderSummary, GraphSummary } from "../contract";
import {
  isGraphDiff,
  isReport,
  type WorkspaceDocument,
} from "./WorkspaceDocument.svelte";
import { SvelteMap, SvelteSet } from "svelte/reactivity";

export interface DocumentOutlineRow {
  type: "document";
  document: WorkspaceDocument;
  depth: number;
}

export type OutlineRow =
  | DocumentOutlineRow
  | { type: "folder"; folder: FolderSummary }
  | { type: "reports"; folderId: string | null }
  | { type: "analyses" }
  | { type: "analysis"; id: string; title: string };

export type ReportDocument = Extract<
  WorkspaceDocument,
  { kind: "simulation-report" | "optimization-report" | "comparison-report" }
>;

export function buildRows(
  documents: readonly WorkspaceDocument[],
  folders: readonly FolderSummary[],
  graphSummaries: readonly GraphSummary[],
): OutlineRow[] {
  const graphsByRevisionId = new SvelteMap<string, WorkspaceDocument>();
  const analysisReports = documents.filter(hasAnalysisMetadata);
  const standardDocuments = documents.filter(
    (document) => !hasAnalysisMetadata(document),
  );

  for (const document of standardDocuments) {
    if (document.kind === "graph" && document.loadedRevisionId) {
      graphsByRevisionId.set(document.loadedRevisionId, document);
    }
  }

  const children = new SvelteMap<string, WorkspaceDocument[]>();
  const roots: WorkspaceDocument[] = [];

  for (const document of standardDocuments) {
    const parent = parentDocument(document, graphsByRevisionId);
    if (parent) {
      const siblings = children.get(parent.id) ?? [];
      siblings.push(document);
      children.set(parent.id, siblings);
    } else {
      roots.push(document);
    }
  }

  const rows: OutlineRow[] = [];
  const visit = (items: readonly WorkspaceDocument[], depth: number): void => {
    for (const document of items) {
      rows.push({ type: "document", document, depth });
      visit(children.get(document.id) ?? [], depth + 1);
    }
  };

  const folderIds = new Set(folders.map((folder) => folder.id));
  const rootsByFolderId = new SvelteMap<string | null, WorkspaceDocument[]>();
  for (const root of roots) {
    const folderId = folderIdForDocument(root, graphSummaries);
    const key = folderId && folderIds.has(folderId) ? folderId : null;
    const groupedRoots = rootsByFolderId.get(key) ?? [];
    groupedRoots.push(root);
    rootsByFolderId.set(key, groupedRoots);
  }

  const appendRoots = (
    items: readonly WorkspaceDocument[],
    depth: number,
    folderId: string | null,
  ): void => {
    const reports = items.filter(isReport);
    visit(
      items.filter((document) => !isReport(document)),
      depth,
    );
    if (reports.length) {
      rows.push({ type: "reports", folderId });
      visit(reports, depth + 1);
    }
  };

  for (const folder of folders) {
    const groupedRoots = rootsByFolderId.get(folder.id) ?? [];
    rows.push({ type: "folder", folder });
    appendRoots(groupedRoots, 1, folder.id);
  }

  appendRoots(rootsByFolderId.get(null) ?? [], 0, null);

  if (analysisReports.length) {
    rows.push({ type: "analyses" });
    const reportsByAnalysis = new SvelteMap<
      string,
      { title: string; reports: WorkspaceDocument[] }
    >();
    for (const report of analysisReports) {
      const title = report.analysisTitle ?? report.analysisId ?? "Analysis";
      const key = report.analysisId ?? title;
      const group = reportsByAnalysis.get(key) ?? { title, reports: [] };
      group.reports.push(report);
      reportsByAnalysis.set(key, group);
    }
    for (const [id, { title, reports }] of reportsByAnalysis) {
      rows.push({ type: "analysis", id, title });
      visit(reports, 1);
    }
  }
  return rows;
}

export function folderIdForGraphId(
  graphId: string,
  graphSummaries: readonly GraphSummary[],
): string | null | undefined {
  return graphSummaries.find((summary) => summary.graph_id === graphId)
    ?.folder_id;
}

export function hasAnalysisMetadata(
  document: WorkspaceDocument,
): document is ReportDocument {
  return (
    isReport(document) && !!(document.analysisId || document.analysisTitle)
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

export function rowKey(row: OutlineRow): string {
  if (row.type === "document") return row.document.id;
  if (row.type === "folder") return `folder-${row.folder.id}`;
  if (row.type === "analyses") return "analyses";
  if (row.type === "analysis") return `analysis-${row.id}`;
  return `reports-${row.folderId ?? "root"}`;
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

  if (document.kind === "document-catalog") return undefined;

  if (!document.loadedRevisionId || !document.graph.parent_revision_id)
    return undefined;

  const parent = graphsByRevisionId.get(document.graph.parent_revision_id);
  if (!parent || parent.id === document.id) return undefined;

  // A malformed parent chain is shown at the root instead of recursing forever.
  const visited = new SvelteSet([document.id]);
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
