import type { GraphContract } from "../../contracts.generated/graph";
import type { GraphDiffResult } from "../../contracts.generated/dashboard/graph";
import type { DocumentCatalogItem } from "../../contracts.generated/dashboard/workspace";
import { describe, expect, it, vi } from "vitest";
import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import { DocumentCatalogDocument } from "../document-catalog/DocumentCatalogDocument.svelte";
import {
  buildDashboardRows,
  dispatchDashboardOutlineSelect,
} from "./build-dashboard-rows";

function graph(
  id: string,
  title: string,
  parentRevisionId: string | null = null,
): EditableGraphDocument {
  const document = new EditableGraphDocument();
  const loadedGraph: GraphContract = {
    id,
    title,
    revision_id: `${id}-r1`,
    parent_revision_id: parentRevisionId,
    revision_kind: "edit",
    revision_number: 1,
    nodes: [],
    edges: [],
  };
  document.replaceFromLoadedGraph(loadedGraph);
  return document;
}

function summary(graphId: string, revisionId: string, folderId?: string) {
  return {
    graph_id: graphId,
    title: graphId,
    revision_id: revisionId,
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    node_count: 0,
    edge_count: 0,
    is_favorite: false,
    folder_id: folderId,
  };
}

function graphDiff(): GraphDiffDocument {
  const graph: GraphContract = {
    id: "base",
    title: "Base",
    revision_id: "base-r1",
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    nodes: [],
    edges: [],
  };
  const result: GraphDiffResult = {
    graph,
    node_status: [],
    edge_status: [],
    node_counts: { added: 0, removed: 0, unchanged: 0 },
    edge_counts: { added: 0, removed: 0, unchanged: 0 },
  };
  return new GraphDiffDocument(
    graph,
    { revisionId: "comparison-r1", title: "Comparison" },
    result,
  );
}

function headers(rows: ReturnType<typeof buildDashboardRows>) {
  return rows.filter((row) => row.type === "header");
}

function items(rows: ReturnType<typeof buildDashboardRows>) {
  return rows.filter((row) => row.type === "item");
}

describe("buildDashboardRows", () => {
  it("groups an open graph tree, report, and comparison in its folder", () => {
    const root = graph("root", "Root");
    const report = new SimulationReportDocument(
      "Root",
      "root",
      root.loadedRevisionId!,
    );
    const comparison = new GraphDiffDocument(
      root.graph,
      { revisionId: "comparison-r1", title: "Comparison" },
      {
        graph: root.graph,
        node_status: [],
        edge_status: [],
        node_counts: { added: 0, removed: 0, unchanged: 0 },
        edge_counts: { added: 0, removed: 0, unchanged: 0 },
      },
    );
    const rows = buildDashboardRows(
      [root, report, comparison],
      [{ id: "folder-1", name: "Threat models" }],
      [summary("root", "root-r1", "folder-1")],
    );

    const folder = headers(rows).find((row) => row.kind === "folder");
    expect(folder?.label).toBe("Threat models");
    expect(folder?.level).toBe(2);

    const byLabel = new Map(items(rows).map((row) => [row.label, row]));
    expect(byLabel.get("Root")?.depth).toBe(1);
    expect(byLabel.get(report.title)?.depth).toBe(2);
    expect(byLabel.get(comparison.title)?.depth).toBe(2);
  });

  it("nests open child graphs and their reports", () => {
    const root = graph("root", "Root");
    const child = graph("child", "Child", root.loadedRevisionId);
    const report = new SimulationReportDocument(
      "Child",
      "child",
      child.loadedRevisionId!,
    );
    const rows = buildDashboardRows([root, child, report], [], []);

    const byLabel = new Map(items(rows).map((row) => [row.label, row]));
    expect(byLabel.get("Root")?.depth).toBe(0);
    expect(byLabel.get("Child")?.depth).toBe(1);
    expect(byLabel.get(report.title)?.depth).toBe(2);
  });

  it("shows a child graph at the root when its parent is closed", () => {
    const child = graph("child", "Child", "closed-parent");
    const rows = buildDashboardRows([child], [], []);

    expect(items(rows)[0]?.depth).toBe(0);
  });

  it("shows the Documents catalog as a root item", () => {
    const catalog = new DocumentCatalogDocument();
    const rows = buildDashboardRows([catalog], [], []);

    const row = items(rows)[0];
    expect(row?.label).toBe("Documents");
    expect(row?.depth).toBe(0);
    expect(row?.drag).toBeUndefined();
  });

  it("builds prefixed related revision and report rows beneath Documents", () => {
    const catalog = new DocumentCatalogDocument();
    const root: DocumentCatalogItem = {
      id: "revision-root",
      kind: "graph",
      graph_id: "graph-related",
      graph_revision_id: "revision-root",
      graph_title: "Related graph",
      revision_kind: "original",
      revision_number: 1,
      created_at: "2026-03-01T00:00:00Z",
    };
    const child: DocumentCatalogItem = {
      ...root,
      id: "revision-child",
      graph_revision_id: "revision-child",
      parent_revision_id: root.graph_revision_id,
      revision_kind: "edit",
      revision_number: 2,
    };
    const report: DocumentCatalogItem = {
      ...child,
      id: "report-child",
      kind: "simulation_report",
    };
    catalog.rememberItems([], [root, child, report]);
    catalog.setChosenKeys([report.id]);

    const rows = buildDashboardRows([catalog], [], []);
    const byId = new Map(items(rows).map((row) => [row.id, row]));
    const rootRow = byId.get(DocumentCatalogDocument.relationNodeId(root));
    const childRow = byId.get(DocumentCatalogDocument.relationNodeId(child));
    const reportRow = byId.get(DocumentCatalogDocument.relationNodeId(report));

    expect(rootRow?.depth).toBe(1);
    expect(childRow?.depth).toBe(2);
    expect(reportRow?.depth).toBe(3);
    expect(rootRow?.id).toMatch(/^catalog-related:/);
    expect(reportRow?.pressed).toBe(true);
  });

  it("opens related rows normally and toggles them with Ctrl or Cmd", () => {
    const open = vi.fn();
    const selectDocument = vi.fn();
    const catalog = new DocumentCatalogDocument(open);
    const related: DocumentCatalogItem = {
      id: "revision-related",
      kind: "graph",
      graph_id: "graph-related",
      graph_revision_id: "revision-related",
      graph_title: "Related graph",
      revision_kind: "original",
      revision_number: 1,
      created_at: "2026-03-01T00:00:00Z",
    };
    catalog.rememberItems([], [related]);
    const id = DocumentCatalogDocument.relationNodeId(related);

    dispatchDashboardOutlineSelect(
      [catalog],
      id,
      { ctrlKey: false, metaKey: false },
      selectDocument,
    );
    expect(open).toHaveBeenCalledWith(related);
    expect(selectDocument).not.toHaveBeenCalled();

    dispatchDashboardOutlineSelect(
      [catalog],
      id,
      { ctrlKey: true, metaKey: false },
      selectDocument,
    );
    expect(catalog.chosenKeys).toEqual([related.id]);
    expect(open).toHaveBeenCalledTimes(1);

    dispatchDashboardOutlineSelect(
      [catalog],
      id,
      { ctrlKey: false, metaKey: true },
      selectDocument,
    );
    expect(catalog.chosenKeys).toEqual([]);

    dispatchDashboardOutlineSelect(
      [catalog],
      "ordinary-document",
      { ctrlKey: true, metaKey: false },
      selectDocument,
    );
    expect(selectDocument).toHaveBeenCalledWith("ordinary-document");
  });

  it("places reports without an open graph in the Reports group", () => {
    const report = new SimulationReportDocument(
      "Closed graph",
      "closed-graph",
      "closed-r1",
    );
    const rows = buildDashboardRows([report], [], []);

    const reports = headers(rows).find((row) => row.label === "Reports");
    expect(reports?.kind).toBe("section");
    expect(reports?.level).toBe(2);
    expect(items(rows)[0]?.depth).toBe(1);
  });

  it("marks draggable graphs with their graph id", () => {
    const root = graph("root", "Root");
    const rows = buildDashboardRows([root], [], []);

    expect(items(rows)[0]?.drag?.data).toBe("root");
  });
});
