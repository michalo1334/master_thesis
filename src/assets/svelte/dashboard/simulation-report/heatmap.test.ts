import type { Node } from "../../contracts.generated/graph";
import type { SimulationReportCharts } from "../../contracts.generated/dashboard/simulation";
import { buildTopologyScene } from "../graph/topology-scene";
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
  return { graph, projection, scene: buildTopologyScene(graph, projection) };
}

function policyGroup(from: string, to: string) {
  const group = scene().scene.policyGroups.find(
    (entry) =>
      entry.group.from_segment_id === from && entry.group.to_segment_id === to,
  );
  expect(group).toBeDefined();
  return group!;
}

function flowGroup(sourceHost: string, targetHost: string) {
  const group = scene().scene.flowGroups.find(
    (entry) =>
      entry.group.source_host_id === sourceHost &&
      entry.group.target_host_id === targetHost,
  );
  expect(group).toBeDefined();
  return group!;
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

it("derives policy heat from projected flow groups, not policy edge ids", () => {
  const appearance = simulationHeatmapAppearance(charts, scene().projection);

  // The policy edge reports 0.95, but only the crossing flow groups count.
  expect(
    appearance.policyAppearance(policyGroup("segment-north", "segment-south")),
  ).toMatchObject({ stroke: "#ea580c" });
});

it("leaves a policy without a matching projected flow unstyled", () => {
  const appearance = simulationHeatmapAppearance(charts, scene().projection);

  expect(
    appearance.policyAppearance(policyGroup("segment-north", "segment-north")),
  ).toBeUndefined();
});

it("leaves policy heat absent without a projection", () => {
  const appearance = simulationHeatmapAppearance(charts, undefined);

  expect(
    appearance.policyAppearance(policyGroup("segment-north", "segment-south")),
  ).toBeUndefined();
});

it("styles each flow group from its own flow ids", () => {
  const appearance = simulationHeatmapAppearance(charts, scene().projection);

  expect(
    appearance.flowAppearance(flowGroup("north-1", "south-1")),
  ).toMatchObject({ stroke: "#15803d" });
  expect(
    appearance.flowAppearance(flowGroup("north-1", "south-2")),
  ).toMatchObject({ stroke: "#ea580c" });
});

it("leaves an untraversed flow group unstyled", () => {
  const appearance = simulationHeatmapAppearance(charts, scene().projection);

  expect(
    appearance.flowAppearance(flowGroup("north-1", "south-3")),
  ).toBeUndefined();
});
