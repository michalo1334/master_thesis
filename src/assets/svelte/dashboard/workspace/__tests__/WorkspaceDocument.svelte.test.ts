import { describe, expect, it } from "vitest";
import { ComparisonReportDocument } from "../../comparison-report/ComparisonReportDocument.svelte";
import { EditableGraphDocument } from "../../graph/EditableGraphDocument.svelte";
import { GraphDiffDocument } from "../../graph/GraphDiffDocument.svelte";
import { OptimizationReportDocument } from "../../optimization-report/OptimizationReportDocument.svelte";
import { SimulationReportDocument } from "../../simulation-report/SimulationReportDocument.svelte";
import { isReport } from "../WorkspaceDocument.svelte";

describe("WorkspaceDocument", () => {
  it("classifies reports polymorphically", () => {
    const graph = new EditableGraphDocument();
    const source = {
      id: "graph-1",
      title: "Topology",
      revision_id: "revision-1",
      parent_revision_id: null,
      revision_kind: "original" as const,
      revision_number: 1,
      nodes: [],
      edges: [],
    };
    const diff = new GraphDiffDocument(
      source,
      { revisionId: "revision-2", title: "Updated topology" },
      {
        graph: source,
        node_status: [],
        edge_status: [],
        node_counts: { added: 0, removed: 0, unchanged: 0 },
        edge_counts: { added: 0, removed: 0, unchanged: 0 },
      },
    );
    const simulation = new SimulationReportDocument(
      "Topology",
      "graph-1",
      "revision-1",
    );
    const optimization = new OptimizationReportDocument({
      graphId: "graph-1",
      graphRevisionId: "revision-1",
      graphTitle: "Topology",
      strategy: "cvss",
      budget: 1,
    });
    const comparison = new ComparisonReportDocument(
      simulation,
      optimization,
      simulation,
    );

    expect(
      [graph, diff, simulation, optimization, comparison].filter(isReport),
    ).toEqual([simulation, optimization, comparison]);
    expect(graph.isAsyncReportDocument()).toBe(false);
    expect(diff.isAsyncReportDocument()).toBe(false);
    expect(simulation.isAsyncReportDocument()).toBe(true);
    expect(optimization.isAsyncReportDocument()).toBe(true);
    expect(comparison.isAsyncReportDocument()).toBe(false);
  });
});
