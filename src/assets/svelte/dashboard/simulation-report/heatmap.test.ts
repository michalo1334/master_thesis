import type { Node } from "../../contracts.generated/graph";
import type { SimulationReportCharts } from "../../contracts.generated/dashboard/simulation";
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
import { expect, it } from "vitest";
import { simulationHeatmapAppearance } from "./heatmap";

/**
 * Traversal heat for `north-1 -> south-1` and `north-1 -> south-2`. The
 * unrelated `policy-*` traversal IDs prove that policy heat never reads policy
 * edge IDs.
 */
const charts: SimulationReportCharts = {
  action_success: [],
  capability_impact: [],
  cdf: [],
  convergence: [],
  edge_traversal: [
    { edge_id: "policy-north-south", traversal_probability: 0.95 },
    { edge_id: "policy-self-north", traversal_probability: 0.9 },
    { edge_id: "flow-db", traversal_probability: 0.1 },
    { edge_id: "flow-api", traversal_probability: 0.6 },
  ],
  histogram: [],
  host_compromise: [{ host_id: "north-1", compromise_probability: 0.8 }],
};

function scene() {
  const graph = graphContract(
    [
      segmentNode("segment-north"),
      segmentNode("segment-south"),
      hostNode("north-1"),
      hostNode("south-1"),
      hostNode("south-2"),
      hostNode("south-3"),
      serviceNode("south-db"),
      serviceNode("south-api"),
      serviceNode("south-cache"),
    ],
    [
      containsEdge("contains-north-1", "segment-north", "north-1"),
      containsEdge("contains-south-1", "segment-south", "south-1"),
      containsEdge("contains-south-2", "segment-south", "south-2"),
      containsEdge("contains-south-3", "segment-south", "south-3"),
      runsEdge("runs-db", "south-1", "south-db"),
      runsEdge("runs-api", "south-2", "south-api"),
      runsEdge("runs-cache", "south-3", "south-cache"),
      reachabilityEdge("policy-north-south", "segment-north", "segment-south"),
      reachabilityEdge("policy-self-north", "segment-north", "segment-north"),
    ],
  );
  const projection = projectionOf({
    segments: [
      segmentRecord("segment-north", ["north-1"]),
      segmentRecord("segment-south", ["south-1", "south-2", "south-3"], {
        service_count: 3,
      }),
    ],
    hosts: [
      hostRecord("north-1", "segment-north"),
      hostRecord("south-1", "segment-south", ["south-db"]),
      hostRecord("south-2", "segment-south", ["south-api"]),
      hostRecord("south-3", "segment-south", ["south-cache"]),
    ],
    services: [
      serviceRecord("south-db", "south-1"),
      serviceRecord("south-api", "south-2"),
      serviceRecord("south-cache", "south-3"),
    ],
    policy_groups: [
      policyGroupRecord("segment-north", "segment-south", [
        "policy-north-south",
      ]),
      policyGroupRecord("segment-north", "segment-north", [
        "policy-self-north",
      ]),
    ],
    flow_groups: [
      flowGroupRecord("north-1", "south-1", ["south-db"], ["flow-db"]),
      flowGroupRecord("north-1", "south-2", ["south-api"], ["flow-api"]),
      flowGroupRecord(
        "north-1",
        "south-3",
        ["south-cache"],
        ["flow-untraversed"],
      ),
    ],
  });
  return { graph, projection };
}

function bundleOf(from: string, to: string) {
  return {
    key: `${from}:${to}`,
    fromSegmentId: from,
    toSegmentId: to,
    isSelf: from === to,
    policyEdgeIds: [],
    flowIds: [],
    serviceIds: [],
    serviceLabels: [],
    detailRows: [],
    connectionCount: 0,
  };
}

function hostNodeById(id: string): Node {
  const node = scene().graph.nodes.find((entry) => entry.id === id);
  expect(node).toBeDefined();
  return node!;
}

it("styles reported hosts from their compromise probability", () => {
  const appearance = simulationHeatmapAppearance(charts, scene().projection);

  expect(appearance.nodeAppearance(hostNodeById("north-1"))).toMatchObject({
    cardFill: "#fee2e2",
    cardStroke: "#b91c1c",
  });
});

it("leaves unreported hosts and non-host nodes unstyled", () => {
  const appearance = simulationHeatmapAppearance(charts, scene().projection);

  expect(appearance.nodeAppearance(hostNodeById("south-1"))).toBeUndefined();
  expect(
    appearance.nodeAppearance({
      id: "segment-north",
      type: "NetworkSegment",
      data: { name: "North", cidr: null },
      view_data: { x_pos: 0, y_pos: 0 },
    }),
  ).toBeUndefined();
});

it("styles a segment-pair bundle with the heat of its projected flows", () => {
  const appearance = simulationHeatmapAppearance(charts, scene().projection);

  // The policy edge reports 0.95, but only the crossing flow groups count.
  expect(
    appearance.bundleAppearance(bundleOf("segment-north", "segment-south")),
  ).toMatchObject({ stroke: "#ea580c" });
  expect(
    appearance.bundleAppearance(bundleOf("segment-north", "segment-north")),
  ).toBeUndefined();
});

it("leaves bundle heat absent without a projection", () => {
  const appearance = simulationHeatmapAppearance(charts, undefined);

  expect(
    appearance.bundleAppearance(bundleOf("segment-north", "segment-south")),
  ).toBeUndefined();
});
