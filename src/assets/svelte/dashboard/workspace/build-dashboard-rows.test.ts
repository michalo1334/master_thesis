import { describe, expect, it } from "vitest";
import type { GraphDiffResult, LoadedGraph } from "../contract";
import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import { DocumentCatalogDocument } from "../document-catalog/DocumentCatalogDocument.svelte";
import { buildDashboardRows } from "./build-dashboard-rows";

function graph(
  id: string,
  title: string,
  parentRevisionId: string | null = null,
): EditableGraphDocument {
  const document = new EditableGraphDocument();
  const loadedGraph: LoadedGraph = {
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
    analysis_ids: [],
    folder_id: folderId,
  };
}

function graphDiff(): GraphDiffDocument {
  const graph: LoadedGraph = {
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

  it("groups analysis reports globally by analysis title", () => {
    const baseline = new SimulationReportDocument(
      "Graph",
      "graph",
      "graph-r1",
      { analysisId: "analysis-1", analysisTitle: "Baseline risk" },
    );
    const other = new SimulationReportDocument(
      "Other graph",
      "other-graph",
      "other-r1",
      { analysisId: "analysis-2", analysisTitle: "Network hardening" },
    );
    const standalone = new SimulationReportDocument(
      "Closed graph",
      "closed",
      "closed-r1",
    );
    const rows = buildDashboardRows([baseline, other, standalone], [], []);

    const labels = headers(rows).map((row) => row.label);
    expect(labels).toContain("Analyses");
    expect(labels).toContain("Baseline risk");
    expect(labels).toContain("Network hardening");
    expect(labels).toContain("Reports");

    const analysis = headers(rows).find((row) => row.label === "Baseline risk");
    expect(analysis?.level).toBe(3);
    expect(items(rows)[0]?.depth).toBe(1);
  });

  it("keeps analyses with equal titles in separate groups", () => {
    const first = new SimulationReportDocument("First", "first", "first-r1", {
      analysisId: "analysis-1",
      analysisTitle: "Generated analysis",
    });
    const second = new SimulationReportDocument(
      "Second",
      "second",
      "second-r1",
      {
        analysisId: "analysis-2",
        analysisTitle: "Generated analysis",
      },
    );
    const rows = buildDashboardRows([first, second], [], []);

    const analysisHeaders = headers(rows).filter(
      (row) => row.label === "Generated analysis",
    );
    expect(analysisHeaders).toHaveLength(2);
  });

  it("marks draggable graphs with their graph id", () => {
    const root = graph("root", "Root");
    const rows = buildDashboardRows([root], [], []);

    expect(items(rows)[0]?.drag?.data).toBe("root");
  });
});
