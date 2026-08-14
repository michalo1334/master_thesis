import { describe, expect, it } from "vitest";
import {
  comparisonMetrics,
  formatDelta,
  formatPercentDelta,
} from "./comparison-report";
import type { SimulationReportData } from "../contract";

function report(capabilityImpact = false): SimulationReportData {
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
      capability_impact: capabilityImpact
        ? [{ capability_id: "mission", down_probability: 0.5 }]
        : [],
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
      expected_mission_impact: 5,
      median_mission_impact: 4,
      mission_impact_p95: 8,
      mission_impact_p99: 10,
      min_mission_impact: 0,
      max_mission_impact: 10,
      mission_impact_variance: 1,
    },
  };
}

describe("comparison report formatting", () => {
  it("shows blast-radius metrics and excludes mission metrics without capabilities", () => {
    expect(comparisonMetrics(report(), report())).toHaveLength(4);
  });

  it("includes mission metrics when the simulation reports capability impact", () => {
    expect(comparisonMetrics(report(true), report())).toHaveLength(8);
  });

  it("formats signed deltas and avoids a percent delta for a zero baseline", () => {
    expect(formatDelta(-2.5)).toBe("-2.5");
    expect(formatPercentDelta(10, 8)).toBe("-20%");
    expect(formatPercentDelta(0, 2)).toBe("—");
  });
});
