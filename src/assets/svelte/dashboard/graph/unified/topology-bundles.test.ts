import type {
  Edge,
  GraphContract,
  Node,
} from "../../../contracts.generated/graph";
import { describe, expect, it } from "vitest";
import {
  graphContract,
  hostNode,
  hostRecord,
  flowGroupRecord,
  policyGroupRecord,
  projectionOf,
  reachabilityEdge,
  segmentNode,
  segmentRecord,
  serviceNode,
  serviceRecord,
} from "../__tests__/topology-fixtures";
import { buildTopologyScene, type TopologyScene } from "../topology-scene";
import {
  buildConnectionBundles,
  buildOutgoingConnectionDetails,
  connectionDetailLabel,
} from "./topology-bundles";

interface Fixture {
  graph: GraphContract;
  scene: TopologyScene;
}

function setServiceName(nodes: Node[], id: string, name: string): void {
  const node = nodes.find((entry) => entry.id === id);
  if (node?.type === "Service") node.data = { ...node.data, name };
}

function fixture({ duplicateServiceLabel = false } = {}): Fixture {
  const nodes: Node[] = [
    segmentNode("segment-a", 40, 40),
    segmentNode("segment-b", 700, 40),
    hostNode("host-a", 60, 140),
    hostNode("host-b", 720, 140),
    serviceNode("svc-zeta", 60, 240),
    serviceNode("svc-alpha", 160, 240),
  ];
  // Labels order differently from ids, so ordering by label is visible.
  setServiceName(nodes, "svc-zeta", "Auth");
  setServiceName(nodes, "svc-alpha", duplicateServiceLabel ? "Auth" : "Cache");

  const edges: Edge[] = [
    reachabilityEdge("policy-ab", "segment-a", "segment-b"),
    reachabilityEdge("policy-ab-2", "segment-a", "segment-b"),
    reachabilityEdge("policy-aa", "segment-a", "segment-a"),
  ];

  const graph = graphContract(nodes, edges);
  const projection = projectionOf({
    segments: [
      segmentRecord("segment-a", ["host-a"]),
      segmentRecord("segment-b", ["host-b"]),
    ],
    hosts: [
      hostRecord("host-a", "segment-a", ["svc-zeta", "svc-alpha"]),
      hostRecord("host-b", "segment-b"),
    ],
    services: [
      serviceRecord("svc-zeta", "host-a"),
      serviceRecord("svc-alpha", "host-a"),
    ],
    policy_groups: [
      policyGroupRecord("segment-a", "segment-b", ["policy-ab", "policy-ab-2"]),
      policyGroupRecord("segment-a", "segment-a", ["policy-aa"]),
      policyGroupRecord("segment-b", "segment-a"),
    ],
    flow_groups: [
      flowGroupRecord(
        "host-a",
        "host-b",
        ["svc-alpha", "svc-zeta"],
        ["flow-1", "flow-2"],
      ),
      flowGroupRecord("host-b", "host-a", [], ["flow-3"]),
    ],
  });

  return { graph, scene: buildTopologyScene(graph, projection) };
}

describe("buildConnectionBundles", () => {
  it("counts unique policy edges plus unique flows per ordered segment pair", () => {
    const { scene } = fixture();

    const bundles = buildConnectionBundles(scene);

    expect(bundles.map((bundle) => bundle.key)).toEqual([
      "segment-a:segment-a",
      "segment-a:segment-b",
      "segment-b:segment-a",
    ]);
    const forward = bundles[1];
    expect(forward.fromSegmentId).toBe("segment-a");
    expect(forward.toSegmentId).toBe("segment-b");
    expect(forward.policyEdgeIds).toEqual(["policy-ab", "policy-ab-2"]);
    expect(forward.flowIds).toEqual(["flow-1", "flow-2"]);
    expect(forward.connectionCount).toBe(4);
  });

  it("lists service labels in deterministic order", () => {
    const { scene } = fixture();

    const forward = buildConnectionBundles(scene)[1];

    expect(forward.serviceIds).toEqual(["svc-zeta", "svc-alpha"]);
    expect(forward.serviceLabels).toEqual(["Auth", "Cache"]);
  });

  it("builds sorted, directional, deduplicated detail rows", () => {
    const { scene } = fixture();
    const forward = buildConnectionBundles(scene)[1];

    expect(forward.detailRows.map(connectionDetailLabel)).toEqual([
      "Auth · host-a → host-b",
      "Cache · host-a → host-b",
    ]);
    expect(
      buildOutgoingConnectionDetails(
        { ...scene, flowGroups: [...scene.flowGroups, scene.flowGroups[0]!] },
        "host-a",
      ).map(connectionDetailLabel),
    ).toEqual(["Auth · host-a → host-b", "Cache · host-a → host-b"]);
  });

  it("deduplicates equal displayed labels across service IDs", () => {
    const { scene } = fixture({ duplicateServiceLabel: true });
    const forward = buildConnectionBundles(scene)[1];

    expect(forward.serviceIds).toEqual(["svc-alpha", "svc-zeta"]);
    expect(forward.detailRows).toEqual([
      expect.objectContaining({
        serviceId: "svc-alpha",
        serviceLabel: "Auth",
        sourceHostId: "host-a",
        targetHostId: "host-b",
      }),
    ]);
    expect(buildOutgoingConnectionDetails(scene, "host-a")).toEqual(
      forward.detailRows,
    );
  });

  it("marks a self pair and counts it without a service", () => {
    const { scene } = fixture();

    const self = buildConnectionBundles(scene)[0];

    expect(self.isSelf).toBe(true);
    expect(self.connectionCount).toBe(1);
    expect(self.serviceLabels).toEqual([]);
  });

  it("keeps a flow-only pair without policy edges", () => {
    const { scene } = fixture();

    const reverse = buildConnectionBundles(scene)[2];

    expect(reverse.policyEdgeIds).toEqual([]);
    expect(reverse.flowIds).toEqual(["flow-3"]);
    expect(reverse.connectionCount).toBe(1);
  });

  it("drops a flow whose host has no projected segment", () => {
    const nodes: Node[] = [
      segmentNode("segment-a", 40, 40),
      hostNode("host-a", 60, 140),
      hostNode("host-orphan", 400, 400),
    ];
    const graph = graphContract(nodes);
    const projection = projectionOf({
      segments: [segmentRecord("segment-a", ["host-a"])],
      hosts: [
        hostRecord("host-a", "segment-a"),
        hostRecord("host-orphan", null),
      ],
      flow_groups: [
        flowGroupRecord("host-a", "host-orphan", [], ["flow-x"]),
        flowGroupRecord("host-orphan", "host-a", [], ["flow-y"]),
      ],
    });
    const scene = buildTopologyScene(graph, projection);

    expect(buildConnectionBundles(scene)).toEqual([]);
  });
});
