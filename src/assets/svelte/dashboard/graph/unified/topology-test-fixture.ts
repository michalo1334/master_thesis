import type {
  Edge,
  GraphContract,
  Node,
} from "../../../contracts.generated/graph";
import type { TopologyProjection } from "../../../contracts.generated/dashboard/graph";
import {
  anchorRecord,
  attachmentRecord,
  containsEdge,
  credentialNode,
  graphContract,
  hostNode,
  hostRecord,
  issueRecord,
  projectionOf,
  runsEdge,
  segmentNode,
  segmentRecord,
  serviceNode,
  serviceRecord,
  storesCredentialEdge,
} from "../__tests__/topology-fixtures";
import { buildTopologyScene, type TopologyScene } from "../topology-scene";

export interface TopologyFixture {
  graph: GraphContract;
  projection: TopologyProjection;
  scene: TopologyScene;
}

/** Entity a semantic edit changed after the accepted projection. */
export const PENDING_ENTITY_ID = "dns-1";
/** Host the projection reports without a segment. */
export const PLACEMENT_ISSUE_ENTITY_ID = "host-7";
/** Service without an owner host. */
export const NO_PLACEMENT_ENTITY_ID = "orphan-svc";
/** Segment membership that names an absent host. */
export const MISSING_REFERENCE_ID = "host-ghost";

/**
 * One scene with every Unplaced status: a placement issue, an entity the
 * projection cannot place, a broken reference, and a pending change.
 *
 * The graph and the projection stay separate, so a test can change one without
 * changing the other.
 */
export function buildTopologyFixture(): TopologyFixture {
  const nodes: Node[] = [
    segmentNode("segment-a", 40, 40),
    hostNode("web-1", 60, 140),
    hostNode("dns-1", 220, 140),
    hostNode("host-7", 60, 520),
    serviceNode("nginx", 60, 240),
    serviceNode("orphan-svc", 380, 520),
    credentialNode("depl-cred", 60, 420),
  ];
  const segment = nodes.find((node) => node.id === "segment-a");
  if (segment?.type === "NetworkSegment") {
    segment.data = { name: "Zone A", cidr: null };
  }

  const edges: Edge[] = [
    containsEdge("contains-web", "segment-a", "web-1"),
    containsEdge("contains-dns", "segment-a", "dns-1"),
    runsEdge("runs-nginx", "web-1", "nginx"),
    storesCredentialEdge("stores-cred", "web-1", "depl-cred"),
  ];

  const graph = graphContract(nodes, edges);
  const projection = projectionOf({
    segments: [
      segmentRecord("segment-a", ["web-1", "dns-1", MISSING_REFERENCE_ID], {
        service_count: 1,
        context_count: 1,
      }),
    ],
    hosts: [
      hostRecord("web-1", "segment-a", ["nginx"], 1),
      hostRecord("dns-1", "segment-a"),
      hostRecord(PLACEMENT_ISSUE_ENTITY_ID, null),
    ],
    services: [
      serviceRecord("nginx", "web-1"),
      serviceRecord(NO_PLACEMENT_ENTITY_ID, null),
    ],
    attachments: [
      attachmentRecord("depl-cred", "Credential", [
        anchorRecord("web-1", "stores-cred", "StoresCredential"),
      ]),
    ],
    issues: [
      issueRecord("host_without_segment", PLACEMENT_ISSUE_ENTITY_ID, [
        "segment-a",
      ]),
    ],
  });

  return {
    graph,
    projection,
    scene: buildTopologyScene(graph, projection, {
      pendingEntityIds: [PENDING_ENTITY_ID],
    }),
  };
}
