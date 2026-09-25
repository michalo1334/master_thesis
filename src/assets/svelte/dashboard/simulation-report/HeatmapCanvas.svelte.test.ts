import type { FetchSimulationReportReply } from "../../contracts.generated/dashboard/simulation";
import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/svelte";
import {
  containsEdge,
  flowGroupRecord,
  graphContract,
  hostNode,
  hostRecord,
  policyGroupRecord,
  projectionOf,
  reachabilityEdge,
  runsEdge,
  segmentNode,
  segmentRecord,
  serviceNode,
  serviceRecord,
} from "../graph/__tests__/topology-fixtures";
import HeatmapCanvas from "./HeatmapCanvas.svelte";
import { SimulationReportDocument } from "./SimulationReportDocument.svelte";

afterEach(cleanup);

/**
 * Report heat: a compromised host, a traversed segment policy, and a traversed
 * operational flow. Each value lands in a distinct heat band.
 */
function heatmapDocument(): SimulationReportDocument {
  const graph = graphContract(
    [
      segmentNode("segment-a", 0, 0),
      segmentNode("segment-b", 700, 0),
      hostNode("host-a1", 40, 120),
      hostNode("host-b1", 740, 120),
      serviceNode("service-a1", 40, 220),
    ],
    [
      containsEdge("contains-a1", "segment-a", "host-a1"),
      containsEdge("contains-b1", "segment-b", "host-b1"),
      runsEdge("runs-a1", "host-a1", "service-a1"),
      reachabilityEdge("policy-ab", "segment-a", "segment-b"),
    ],
  );
  const projection = projectionOf({
    segments: [
      segmentRecord("segment-a", ["host-a1"], { service_count: 1 }),
      segmentRecord("segment-b", ["host-b1"]),
    ],
    hosts: [
      hostRecord("host-a1", "segment-a", ["service-a1"]),
      hostRecord("host-b1", "segment-b"),
    ],
    services: [serviceRecord("service-a1", "host-a1")],
    policy_groups: [policyGroupRecord("segment-a", "segment-b", ["policy-ab"])],
    flow_groups: [
      flowGroupRecord("host-a1", "host-b1", ["service-a1"], ["flow-1"]),
    ],
  });

  const report = new SimulationReportDocument(
    "Topology",
    "graph-1",
    "revision-1",
  );
  report.markReady("experiment-1");
  report.setReportData({
    experiment_id: "experiment-1",
    graph_id: "graph-1",
    graph_revision_id: "revision-1",
    graph_title: "Topology",
    run_count: 1,
    iteration_count: 1,
    total_runtime_ms: 1,
    feasible: true,
    graph,
    topology_projection: projection,
    capability_statuses: [],
    summary: {},
    charts: {
      action_success: [],
      capability_impact: [],
      cdf: [],
      convergence: [],
      edge_traversal: [
        { edge_id: "policy-ab", traversal_probability: 0.6 },
        { edge_id: "flow-1", traversal_probability: 0.3 },
      ],
      histogram: [],
      host_compromise: [{ host_id: "host-a1", compromise_probability: 0.8 }],
    },
  } as unknown as FetchSimulationReportReply);

  return report;
}

function styleProperty(selector: string, property: string): string {
  const element = document.querySelector<SVGElement>(selector);
  expect(element).not.toBeNull();
  return element!.style.getPropertyValue(property);
}

describe("HeatmapCanvas", () => {
  it("colors hosts, segment policies, and operational flows by their heat", () => {
    render(HeatmapCanvas, { props: { document: heatmapDocument() } });

    expect(styleProperty('[data-node-id="host-a1"]', "--node-card-fill")).toBe(
      "#fee2e2",
    );
    // The policy edge reports 0.6, but policy heat comes from the crossing flow
    // group at 0.3, never from the policy edge's own traversal ID.
    expect(styleProperty(".topology-policy", "--policy-stroke")).toBe(
      "#ca8a04",
    );
    expect(styleProperty(".topology-flow", "--flow-stroke")).toBe("#ca8a04");
  });

  it("offers no Topology and Network view toggle", () => {
    render(HeatmapCanvas, { props: { document: heatmapDocument() } });

    expect(screen.queryByRole("button", { name: "Topology" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Network" })).toBeNull();
  });

  it("reports missing grouping instead of drawing an ungrouped graph", () => {
    const report = new SimulationReportDocument("Topology", "graph-1", "r1");
    report.markReady("experiment-1");
    report.heatmapGraph = graphContract([hostNode("host-a1")]);

    render(HeatmapCanvas, { props: { document: report } });

    expect(
      screen.getByText("Topology grouping is unavailable for this report."),
    ).toBeInTheDocument();
  });
});
