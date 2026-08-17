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
    capability_statuses: [],
    feasible: true,
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

  it("renders optional feasibility and capability-status fields", () => {
    const baseline = {
      ...report(),
      graph: {
        ...report().graph,
        nodes: [
          {
            id: "capability-1",
            type: "MissionCapability",
            data: {
              name: "Order entry",
              impact_weight: 1,
              min_operational_support: 1,
            },
            view_data: { x_pos: 0, y_pos: 0 },
          },
        ],
      },
      capability_statuses: [
        {
          capability_id: "capability-1",
          operational: true,
          required_flow_count: 3,
          missing_flow_count: 1,
          supporting_host_count: 2,
          min_operational_support: 2,
        },
      ],
      charts: {
        ...report().charts,
        capability_impact: [
          { capability_id: "capability-1", down_probability: 0.6 },
        ],
      },
    } as unknown as SimulationReportData;
    const defended = {
      ...baseline,
      feasible: true,
      capability_statuses: [
        {
          capability_id: "capability-1",
          operational: false,
          required_flow_count: 3,
          missing_flow_count: 0,
          supporting_host_count: 1,
          min_operational_support: 2,
        },
      ],
      charts: {
        ...baseline.charts,
        capability_impact: [
          { capability_id: "capability-1", down_probability: 0.2 },
        ],
      },
    } as unknown as SimulationReportData;
    const document = {
      title: "Comparison for Topology",
      baselineReport: { status: "loaded", reportData: baseline },
      postOptimizationReport: { status: "loaded", reportData: defended },
      optimizationReport: {
        status: "loaded",
        reportData: {
          strategy: "cvss",
          requested_budget: 1,
          used_budget: 1,
          runtime_ms: 1,
          actions: [],
        },
        graphDiff: undefined,
        graphDiffStatus: "",
      },
    } as unknown as ComparisonReportDocument;

    render(ComparisonReport, { props: { document } });

    expect(screen.getByText("Pre-attack feasibility")).toBeInTheDocument();
    expect(screen.getByText("Feasible")).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Mission capability status" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("heading", {
        name: "Mission capability disruption probability",
      }),
    ).toBeInTheDocument();
    expect(screen.getByText("Unavailable")).toBeInTheDocument();
    expect(screen.getByText("60%")).toBeInTheDocument();
    expect(screen.getByText("20%")).toBeInTheDocument();
    expect(screen.getByText("-40 pp")).toBeInTheDocument();
    expect(screen.getByText("2 / 3")).toBeInTheDocument();
    expect(screen.getByText("3 / 3")).toBeInTheDocument();
    expect(screen.getByText("2 / 2")).toBeInTheDocument();
    expect(screen.getByText("1 / 2")).toBeInTheDocument();
  });
});
