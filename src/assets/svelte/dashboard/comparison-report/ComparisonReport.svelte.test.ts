import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/svelte";
import ComparisonReport from "./ComparisonReport.svelte";
import type { ComparisonReportDocument } from "./ComparisonReportDocument.svelte";
import type { SimulationReportData } from "../contract";

afterEach(cleanup);

function report(): SimulationReportData {
  return {
    experiment_id: "experiment",
    graph_id: "graph",
    graph_revision_id: "revision",
    graph_title: "Topology",
    iteration_count: 1,
    run_count: 1,
    total_runtime_ms: 1,
    graph: {
      id: "graph",
      title: "Topology",
      revision_id: "revision",
      parent_revision_id: null,
      revision_kind: "original",
      revision_number: 1,
      nodes: [],
      edges: [],
    },
    charts: {
      action_success: [],
      capability_impact: [],
      cdf: [],
      convergence: [],
      edge_traversal: [],
      histogram: [],
      host_compromise: [],
    },
    operational_flows: [],
    summary: {
      expected_blast_radius: 10,
      median_blast_radius: 8,
      blast_radius_p95: 16,
      blast_radius_p99: 20,
      min_blast_radius: 0,
      max_blast_radius: 20,
      blast_radius_variance: 1,
      host_count: 20,
      expected_mission_impact: 0,
      median_mission_impact: 0,
      mission_impact_p95: 0,
      mission_impact_p99: 0,
      min_mission_impact: 0,
      max_mission_impact: 0,
      mission_impact_variance: 0,
    },
  };
}

describe("ComparisonReport", () => {
  it("renders complete metric cards for the narrow-screen layout", () => {
    const document = {
      title: "Comparison for Topology",
      baselineReport: { status: "loaded", reportData: report() },
      postOptimizationReport: {
        status: "loaded",
        reportData: {
          ...report(),
          summary: { ...report().summary, expected_blast_radius: 8 },
        },
      },
      optimizationReport: {
        status: "loaded",
        reportData: {
          strategy: "cvss",
          objective: "blast_radius",
          requested_budget: 1,
          used_budget: 1,
          runtime_ms: 1,
          actions: [],
        },
        graphDiff: undefined,
        graphDiffStatus: "",
      },
    } as unknown as ComparisonReportDocument;

    const { container } = render(ComparisonReport, { props: { document } });

    expect(screen.getByRole("table")).toBeInTheDocument();
    expect(
      container.querySelectorAll(".comparison-report-metric-cards li"),
    ).toHaveLength(4);
    expect(screen.getAllByText("Absolute delta")).toHaveLength(5);
    expect(screen.getAllByText("-2")).toHaveLength(2);
  });
});
