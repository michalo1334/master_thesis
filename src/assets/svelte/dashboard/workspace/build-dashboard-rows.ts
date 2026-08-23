import {
  buildOutline,
  type OutlineGroup,
  type OutlineNode,
  type OutlineRow,
} from "../../ui-kit/workspace/outline";
import {
  folderIdForDocument,
  graphIdForDocument,
  hasAnalysisMetadata,
  parentDocument,
} from "./document-outline";
import { isReport, type WorkspaceDocument } from "./WorkspaceDocument.svelte";
import type { FolderSummary, GraphSummary } from "../contract";
import { DocumentCatalogDocument } from "../document-catalog/DocumentCatalogDocument.svelte";

export interface OutlineSelectModifiers {
  ctrlKey: boolean;
  metaKey: boolean;
}

/**
 * App-specific adapter: maps domain (documents + folders + graphSummaries)
 * to normalized outline nodes the kit's buildOutline assembles.
 */
export function buildDashboardNodes(
  documents: readonly WorkspaceDocument[],
  folders: readonly FolderSummary[],
  graphSummaries: readonly GraphSummary[],
): OutlineNode<string>[] {
  const graphsByRevisionId = new Map<string, WorkspaceDocument>();
  const folderIds = new Set(folders.map((f) => f.id));
  for (const d of documents)
    if (d.kind === "graph" && d.loadedRevisionId)
      graphsByRevisionId.set(d.loadedRevisionId, d);

  const documentNodes = documents.map((d) => {
    if (hasAnalysisMetadata(d)) {
      return {
        id: d.id,
        label: d.title,
        icon: d.icon,
        kind: d.kind,
        groupId: "analyses",
        section: {
          key: d.analysisId ?? d.analysisTitle ?? "Analysis",
          title: d.analysisTitle ?? d.analysisId ?? "Analysis",
        },
        ariaLabel: `${d.documentLabel} ${d.title}`,
      };
    }

    const parent = parentDocument(d, graphsByRevisionId);
    const folderId = folderIdForDocument(d, graphSummaries);
    const groupId = folderId && folderIds.has(folderId) ? folderId : "root";
    const graphId = graphIdForDocument(d);
    return {
      id: d.id,
      label: d.title,
      icon: d.icon,
      kind: d.kind,
      groupId,
      parentId: parent?.id,
      section:
        !parent && isReport(d)
          ? { key: "reports", title: "Reports" }
          : undefined,
      ariaLabel: `${d.documentLabel} ${d.title}`,
      drag: graphId ? { data: graphId } : undefined,
    };
  });

  const relatedNodes = documents.flatMap((document) =>
    document.kind === "document-catalog"
      ? buildRelatedCatalogNodes(document)
      : [],
  );

  return [...documentNodes, ...relatedNodes];
}

function buildRelatedCatalogNodes(
  document: DocumentCatalogDocument,
): OutlineNode<string>[] {
  const revisions = new Map(
    document.relatedItems
      .filter((item) => item.kind === "graph")
      .map(
        (item) =>
          [
            item.graph_revision_id,
            DocumentCatalogDocument.relationNodeId(item),
          ] as const,
      ),
  );

  return document.relatedItems.map((item) => ({
    id: DocumentCatalogDocument.relationNodeId(item),
    label: DocumentCatalogDocument.relationLabel(item),
    icon: DocumentCatalogDocument.relationIcon(item),
    kind: item.kind,
    groupId: "root",
    parentId:
      item.kind === "graph"
        ? (item.parent_revision_id && revisions.get(item.parent_revision_id)) ||
          document.id
        : revisions.get(item.graph_revision_id) || document.id,
    ariaLabel: `${DocumentCatalogDocument.kindLabel(item.kind)} ${DocumentCatalogDocument.relationLabel(item)}`,
    pressed: document.chosenKeys.includes(item.id),
  }));
}

export function dispatchDashboardOutlineSelect(
  documents: readonly WorkspaceDocument[],
  id: string,
  modifiers: OutlineSelectModifiers,
  selectDocument: (id: string) => void,
): void {
  if (!id.startsWith(DocumentCatalogDocument.relationNodePrefix)) {
    selectDocument(id);
    return;
  }

  const catalog = documents.find(
    (document) => document.kind === "document-catalog",
  ) as DocumentCatalogDocument | undefined;
  const item = catalog?.relationItem(id);
  if (!catalog || !item) return;

  if (modifiers.ctrlKey || modifiers.metaKey) {
    catalog.toggleChosen(item.id);
  } else {
    void catalog.openItem(item);
  }
}

export function buildDashboardGroups(
  folders: readonly FolderSummary[],
  hasAnalyses: boolean,
): OutlineGroup<string>[] {
  return [
    ...folders.map((f) => ({
      id: f.id,
      label: f.name,
      icon: "folder",
      depth: 1,
      drop: { data: f.id },
    })),
    ...(hasAnalyses ? [{ id: "analyses", label: "Analyses", depth: 0 }] : []),
  ];
}

export function buildDashboardRows(
  documents: readonly WorkspaceDocument[],
  folders: readonly FolderSummary[],
  graphSummaries: readonly GraphSummary[],
): OutlineRow<string, string>[] {
  const nodes = buildDashboardNodes(documents, folders, graphSummaries);
  const groups = buildDashboardGroups(
    folders,
    nodes.some((n) => n.groupId === "analyses"),
  );
  return buildOutline(nodes, groups);
}

export type { OutlineRow };
