import type {
  Edge,
  GraphContract,
  Node,
} from "../../../contracts.generated/graph";
import { describe, expect, it } from "vitest";
import {
  anchorRecord,
  attachmentRecord,
  containsEdge,
  credentialNode,
  flowGroupRecord,
  graphContract,
  hasVulnerabilityEdge,
  hostNode,
  hostRecord,
  issueRecord,
  policyGroupRecord,
  projectionOf,
  reachabilityEdge,
  runsEdge,
  segmentNode,
  segmentRecord,
  serviceNode,
  serviceRecord,
  storesCredentialEdge,
  vulnerabilityNode,
} from "../../graph/__tests__/topology-fixtures";
import { selectionTopology } from "./selection-topology";

interface Fixture {
  graph: GraphContract;
  projection: ReturnType<typeof projectionOf>;
  node: (id: string) => Node;
}

function fixture(): Fixture {
  const nodes: Node[] = [
    segmentNode("zone-north"),
    segmentNode("zone-south"),
    hostNode("north-1"),
    hostNode("north-2"),
    serviceNode("north-db"),
    credentialNode("credential-1"),
    { ...hostNode("orphan-1") } as Node,
  ];
  const named = nodes.map((node) =>
    node.type === "NetworkSegment"
      ? { ...node, data: { name: `Segment ${node.id}`, cidr: null } }
      : node,
  );
  const edges: Edge[] = [
    containsEdge("contains-north-1", "zone-north", "north-1"),
    containsEdge("contains-north-2", "zone-north", "north-2"),
    runsEdge("runs-north-db", "north-1", "north-db"),
    storesCredentialEdge("stores-credential-1", "north-1", "credential-1"),
    reachabilityEdge("policy-north-south", "zone-north", "zone-south"),
  ];

  const projection = projectionOf({
    segments: [
      segmentRecord("zone-north", ["north-1", "north-2"], {
        service_count: 1,
        context_count: 1,
      }),
      segmentRecord("zone-south", []),
    ],
    hosts: [
      hostRecord("north-1", "zone-north", ["north-db"], 1),
      hostRecord("north-2", "zone-north"),
    ],
    services: [serviceRecord("north-db", "north-1")],
    attachments: [
      attachmentRecord("credential-1", "Credential", [
        anchorRecord("north-1", "stores-credential-1", "StoresCredential"),
      ]),
    ],
    policy_groups: [
      policyGroupRecord("zone-north", "zone-south", ["policy-north-south"]),
      policyGroupRecord("zone-south", "zone-south", []),
    ],
    flow_groups: [
      flowGroupRecord("north-1", "north-2", ["north-db"], ["flow-1", "flow-2"]),
    ],
    issues: [issueRecord("host_without_segment", "orphan-1")],
  });

  const graph = graphContract(named, edges);
  return {
    graph,
    projection,
    node: (id) => graph.nodes.find((entry) => entry.id === id)!,
  };
}

describe("selectionTopology", () => {
  it("reports nothing without a projection or for an edge", () => {
    const { graph } = fixture();
    const node = graph.nodes.find((entry) => entry.id === "north-1")!;

    expect(selectionTopology(graph, node)).toEqual({
      placement: null,
      relationships: [],
      draftReachability: false,
    });

    const { projection } = fixture();
    const edge = graph.edges[0]!;
    expect(
      selectionTopology(graph, edge, { projection }).relationships,
    ).toEqual([]);
  });

  it("summarizes the membership, services, anchors, and flows of a host", () => {
    const { graph, projection, node } = fixture();
    const summary = selectionTopology(graph, node("north-1"), { projection });

    expect(summary.placement).toBeNull();
    expect(summary.relationships).toEqual([
      "Member of Segment zone-north",
      "Segment policy to Segment zone-south · 1 relationship",
      "Runs north-db",
      "StoresCredential · credential-1",
      "Operational flow north-1 → north-2 · 2 relationships",
    ]);
    expect(summary.draftReachability).toBe(false);
  });

  it("flags draft reachability only for an entity with visible flows", () => {
    const { graph, projection, node } = fixture();
    const options = { projection, projectionSource: "draft" as const };

    expect(
      selectionTopology(graph, node("north-2"), options).draftReachability,
    ).toBe(true);
    expect(
      selectionTopology(graph, node("north-db"), options).draftReachability,
    ).toBe(true);
    expect(
      selectionTopology(graph, node("zone-south"), options).draftReachability,
    ).toBe(false);
  });

  it("summarizes a segment with its members, policy, and self policy", () => {
    const { graph, projection, node } = fixture();
    const summary = selectionTopology(graph, node("zone-north"), {
      projection,
    });

    expect(summary.relationships).toEqual([
      "Segment policy to Segment zone-south · 1 relationship",
      "Contains north-1",
      "StoresCredential · credential-1",
      "Contains north-2",
      "Operational flow north-1 → north-2 · 2 relationships",
    ]);
  });

  it("keeps distinct attached context rows for one host", () => {
    const nodes: Node[] = [
      segmentNode("zone-north"),
      hostNode("north-1"),
      vulnerabilityNode("vuln-1"),
      credentialNode("credential-2"),
    ];
    const edges: Edge[] = [
      containsEdge("contains-north-1", "zone-north", "north-1"),
      hasVulnerabilityEdge("has-vuln-1", "north-1", "vuln-1"),
      storesCredentialEdge("stores-credential-2", "north-1", "credential-2"),
    ];
    const graph = graphContract(nodes, edges);
    const projection = projectionOf({
      segments: [
        segmentRecord("zone-north", ["north-1"], { context_count: 2 }),
      ],
      hosts: [hostRecord("north-1", "zone-north", [], 2)],
      attachments: [
        attachmentRecord("credential-2", "Credential", [
          anchorRecord("north-1", "stores-credential-2", "StoresCredential"),
        ]),
        attachmentRecord("vuln-1", "Vulnerability", [
          anchorRecord("north-1", "has-vuln-1", "HasVulnerability"),
        ]),
      ],
    });

    const summary = selectionTopology(
      graph,
      graph.nodes.find((entry) => entry.id === "north-1")!,
      { projection },
    );

    // Each row names the attached context entity, so two attachments to the
    // same host stay distinct instead of collapsing onto the anchor host.
    expect(summary.relationships).toEqual([
      "Member of zone-north",
      "StoresCredential · credential-2",
      "HasVulnerability · vuln-1",
    ]);
  });

  it("summarizes the owner host of a service", () => {
    const { graph, projection, node } = fixture();
    const summary = selectionTopology(graph, node("north-db"), { projection });

    expect(summary.relationships).toContain("Runs on north-1");
    expect(summary.relationships).toContain("Member of Segment zone-north");
    expect(summary.relationships).toContain(
      "Operational flow north-1 → north-2 · 2 relationships",
    );
  });

  it("summarizes the anchors of an attached context node", () => {
    const { graph, projection, node } = fixture();
    const summary = selectionTopology(graph, node("credential-1"), {
      projection,
    });

    // The anchor relationship comes first, then the flows the anchor host
    // participates in.
    expect(summary.relationships).toEqual([
      "StoresCredential · north-1",
      "Operational flow north-1 → north-2 · 2 relationships",
    ]);
    expect(summary.draftReachability).toBe(false);
  });

  it("reports the typed placement issue of an unplaced entity", () => {
    const { graph, projection, node } = fixture();
    const summary = selectionTopology(graph, node("orphan-1"), { projection });

    expect(summary.placement).toEqual({
      status: "placement_issue",
      reasonCode: "host_without_segment",
      reason: "no segment",
    });
  });
});
