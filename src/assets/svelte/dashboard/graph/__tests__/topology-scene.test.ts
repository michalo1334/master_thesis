import { describe, expect, it, vi } from "vitest";
import { buildTopologyScene, unplacedSelection } from "../topology-scene";
import {
  anchorRecord,
  attachmentRecord,
  authenticatesToEdge,
  containsEdge,
  credentialNode,
  flowGroupRecord,
  graphContract,
  hasVulnerabilityEdge,
  hostNode,
  hostRecord,
  issueRecord,
  missionCapabilityNode,
  policyGroupRecord,
  projectionOf,
  reachabilityEdge,
  runsEdge,
  segmentNode,
  segmentRecord,
  serviceNode,
  serviceRecord,
  supportsEdge,
  vulnerabilityNode,
} from "./topology-fixtures";

describe("buildTopologyScene", () => {
  it("joins segment, host, and service records to their graph entities", () => {
    const graph = graphContract([
      segmentNode("segment-1", 40, 60),
      hostNode("host-1"),
      hostNode("host-2"),
      serviceNode("service-1"),
      serviceNode("service-2"),
    ]);
    const projection = projectionOf({
      segments: [
        segmentRecord("segment-1", ["host-1", "host-2"], { service_count: 2 }),
      ],
      hosts: [
        hostRecord("host-1", "segment-1", ["service-1", "service-2"]),
        hostRecord("host-2", "segment-1"),
      ],
      services: [
        serviceRecord("service-1", "host-1"),
        serviceRecord("service-2", "host-1"),
      ],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.segments).toHaveLength(1);
    const segment = scene.segments[0]!;
    expect(segment.node).toBe(graph.nodes[0]);
    expect(segment.hosts.map((host) => host.id)).toEqual(["host-1", "host-2"]);
    expect(segment.hosts[0]!.services.map((service) => service.id)).toEqual([
      "service-1",
      "service-2",
    ]);
    expect(segment.hosts[0]!.services[0]!.hostId).toBe("host-1");
    expect(scene.unplaced).toEqual([]);
  });

  it("derives no membership, ownership, or anchors from raw edges", () => {
    const graph = graphContract(
      [
        segmentNode("segment-1"),
        hostNode("host-1"),
        serviceNode("service-1"),
        vulnerabilityNode("vulnerability-1"),
      ],
      [
        containsEdge("contains-1", "segment-1", "host-1"),
        runsEdge("runs-1", "host-1", "service-1"),
        hasVulnerabilityEdge(
          "has-vulnerability-1",
          "service-1",
          "vulnerability-1",
        ),
        reachabilityEdge("reachability-1", "segment-1", "segment-1"),
      ],
    );

    const scene = buildTopologyScene(graph, projectionOf({}));

    expect(scene.segments).toEqual([]);
    expect(scene.attachments).toEqual([]);
    expect(scene.policyGroups).toEqual([]);
    expect(scene.flowGroups).toEqual([]);
    expect(
      scene.unplaced.map((entry) => [entry.status, entry.entityId]),
    ).toEqual([
      ["no_placement", "host-1"],
      ["no_placement", "segment-1"],
      ["no_placement", "service-1"],
      ["no_placement", "vulnerability-1"],
    ]);
  });

  it("follows the projection when a raw edge claims different membership", () => {
    const graph = graphContract(
      [segmentNode("segment-1"), hostNode("host-1"), hostNode("host-2")],
      [containsEdge("contains-1", "segment-1", "host-2")],
    );
    const projection = projectionOf({
      segments: [segmentRecord("segment-1", ["host-1"])],
      hosts: [hostRecord("host-1", "segment-1"), hostRecord("host-2", null)],
      issues: [issueRecord("host_without_segment", "host-2")],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.segments[0]!.hosts.map((host) => host.id)).toEqual(["host-1"]);
    expect(
      scene.unplaced.map((entry) => [entry.entityId, entry.status]),
    ).toEqual([["host-2", "placement_issue"]]);
  });

  it("copies projector issues and exposes the affected entity", () => {
    const graph = graphContract([hostNode("host-3")]);
    const projection = projectionOf({
      hosts: [hostRecord("host-3", null)],
      issues: [
        issueRecord("host_without_segment", "host-3"),
        issueRecord("service_multiple_hosts", "service-9", [
          "host-1",
          "host-2",
        ]),
      ],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.issues).toHaveLength(2);
    const entry = scene.unplaced.find((item) => item.entityId === "host-3")!;
    expect(entry.status).toBe("placement_issue");
    expect(entry.node?.id).toBe("host-3");
    expect(entry.issue?.code).toBe("host_without_segment");
    expect(entry.missing).toBeNull();

    const orphan = scene.unplaced.find(
      (item) => item.entityId === "service-9",
    )!;
    expect(orphan.node).toBeNull();
    expect(orphan.issue?.related_ids).toEqual(["host-1", "host-2"]);
  });

  it("reports projection references that have no graph entity", () => {
    const graph = graphContract([segmentNode("segment-1"), hostNode("host-1")]);
    const projection = projectionOf({
      segments: [
        segmentRecord("segment-1", ["host-1", "host-missing"]),
        segmentRecord("segment-ghost"),
      ],
      hosts: [
        hostRecord("host-1", "segment-ghost"),
        hostRecord("host-ghost", null),
      ],
      services: [serviceRecord("service-ghost", "host-1")],
    });

    const scene = buildTopologyScene(graph, projection);

    const missing = scene.unplaced.map((entry) => [
      entry.status,
      entry.entityId,
      entry.missing?.relationship,
      entry.missing?.ownerIds,
    ]);
    expect(missing).toEqual([
      ["missing_reference", "host-ghost", "host_node", ["host-ghost"]],
      ["missing_reference", "host-missing", "host_node", ["segment-1"]],
      ["missing_reference", "host-1", "segment_host", ["segment-1"]],
      [
        "missing_reference",
        "segment-ghost",
        "segment_node",
        ["host-1", "segment-ghost"],
      ],
      ["missing_reference", "service-ghost", "service_node", ["service-ghost"]],
    ]);
    expect(scene.segments.map((segment) => segment.id)).toEqual(["segment-1"]);
    expect(scene.segments[0]!.hosts.map((host) => host.id)).toEqual(["host-1"]);
  });

  it("deduplicates missing references by relationship and reference id", () => {
    const graph = graphContract([
      segmentNode("segment-1"),
      segmentNode("segment-2"),
    ]);
    const projection = projectionOf({
      segments: [
        segmentRecord("segment-1", ["host-ghost"]),
        segmentRecord("segment-2", ["host-ghost"]),
      ],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.unplaced).toHaveLength(1);
    expect(scene.unplaced[0]!.missing).toEqual({
      relationship: "host_node",
      referenceId: "host-ghost",
      ownerIds: ["segment-1", "segment-2"],
    });
  });

  it("lists graph entities that the accepted projection does not place", () => {
    const graph = graphContract(
      [
        segmentNode("segment-1"),
        hostNode("host-1"),
        hostNode("host-2"),
        serviceNode("service-1"),
        serviceNode("service-2"),
        vulnerabilityNode("vulnerability-1"),
      ],
      [
        containsEdge("contains-1", "segment-1", "host-2"),
        runsEdge("runs-1", "host-2", "service-2"),
        hasVulnerabilityEdge(
          "has-vulnerability-1",
          "host-2",
          "vulnerability-1",
        ),
      ],
    );
    const projection = projectionOf({
      segments: [segmentRecord("segment-1", ["host-1"])],
      hosts: [hostRecord("host-1", "segment-1")],
      services: [serviceRecord("service-1", "host-1")],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.segments[0]!.hosts.map((host) => host.id)).toEqual(["host-1"]);
    expect(
      scene.unplaced.map((entry) => [
        entry.status,
        entry.entityId,
        entry.node?.type,
      ]),
    ).toEqual([
      ["no_placement", "host-2", "Host"],
      ["no_placement", "service-2", "Service"],
      ["no_placement", "vulnerability-1", "Vulnerability"],
    ]);
  });

  it("lists an owned service when no segment claims its host", () => {
    const graph = graphContract([
      segmentNode("segment-1"),
      hostNode("host-1"),
      hostNode("host-2"),
      serviceNode("service-1"),
      serviceNode("service-2"),
    ]);
    const projection = projectionOf({
      segments: [segmentRecord("segment-1", ["host-2"])],
      hosts: [hostRecord("host-1", null), hostRecord("host-2", "segment-1")],
      services: [
        serviceRecord("service-1", "host-1"),
        serviceRecord("service-2", "host-2"),
      ],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.segments[0]!.hosts.map((host) => host.id)).toEqual(["host-2"]);
    expect(scene.segments[0]!.hosts[0]!.services.map((s) => s.id)).toEqual([
      "service-2",
    ]);
    expect(
      scene.unplaced.map((entry) => [
        entry.status,
        entry.entityId,
        entry.node?.type,
      ]),
    ).toEqual([
      ["no_placement", "host-1", "Host"],
      ["no_placement", "service-1", "Service"],
    ]);
    const service = scene.unplaced.find(
      (entry) => entry.entityId === "service-1",
    )!;
    expect(service.issue).toBeNull();
    expect(service.missing).toBeNull();
  });

  it("lists an owned service when its host record contradicts membership", () => {
    const graph = graphContract([
      segmentNode("segment-1"),
      hostNode("host-1"),
      serviceNode("service-1"),
    ]);
    const projection = projectionOf({
      segments: [segmentRecord("segment-1")],
      hosts: [hostRecord("host-1", "segment-1", ["service-1"])],
      services: [serviceRecord("service-1", "host-1")],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.segments[0]!.hosts).toEqual([]);
    expect(
      scene.unplaced.map((entry) => [
        entry.status,
        entry.entityId,
        entry.missing?.relationship,
      ]),
    ).toEqual([
      ["no_placement", "service-1", undefined],
      ["missing_reference", "host-1", "segment_host"],
    ]);
  });

  it("keeps an owned service placed when a segment claims its host", () => {
    const graph = graphContract([
      segmentNode("segment-1"),
      hostNode("host-1"),
      serviceNode("service-1"),
    ]);
    const projection = projectionOf({
      segments: [segmentRecord("segment-1", ["host-1"])],
      hosts: [hostRecord("host-1", null, ["service-1"])],
      services: [serviceRecord("service-1", "host-1")],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.segments[0]!.hosts[0]!.services.map((s) => s.id)).toEqual([
      "service-1",
    ]);
    expect(scene.unplaced.map((entry) => entry.entityId)).toEqual(["host-1"]);
    expect(scene.unplaced[0]!.status).toBe("missing_reference");
  });

  it("does not duplicate a placement issue for an unplaced service owner", () => {
    const graph = graphContract([
      hostNode("host-1"),
      hostNode("host-2"),
      serviceNode("service-1"),
    ]);
    const projection = projectionOf({
      hosts: [hostRecord("host-1", null), hostRecord("host-2", null)],
      services: [serviceRecord("service-1", "host-1")],
      issues: [
        issueRecord("service_multiple_hosts", "service-1", [
          "host-1",
          "host-2",
        ]),
      ],
    });

    const scene = buildTopologyScene(graph, projection);

    const serviceEntries = scene.unplaced.filter(
      (entry) => entry.entityId === "service-1",
    );
    expect(serviceEntries).toHaveLength(1);
    expect(serviceEntries[0]!.status).toBe("placement_issue");
    expect(serviceEntries[0]!.issue?.related_ids).toEqual(["host-1", "host-2"]);
  });

  it("reports membership that the segment record omits", () => {
    const graph = graphContract([segmentNode("segment-1"), hostNode("host-1")]);
    const projection = projectionOf({
      segments: [segmentRecord("segment-1")],
      hosts: [hostRecord("host-1", "segment-1")],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.segments[0]!.hosts).toEqual([]);
    expect(
      scene.unplaced.map((entry) => [
        entry.status,
        entry.entityId,
        entry.missing?.relationship,
        entry.missing?.ownerIds,
      ]),
    ).toEqual([["missing_reference", "host-1", "segment_host", ["segment-1"]]]);
  });

  it("reports a segment that lists a host the host record places elsewhere", () => {
    const graph = graphContract([
      segmentNode("segment-1"),
      segmentNode("segment-2"),
      hostNode("host-1"),
    ]);
    const projection = projectionOf({
      segments: [
        segmentRecord("segment-1", ["host-1"]),
        segmentRecord("segment-2"),
      ],
      hosts: [hostRecord("host-1", "segment-2")],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.segments[0]!.hosts.map((host) => host.id)).toEqual(["host-1"]);
    expect(scene.unplaced.map((entry) => entry.missing)).toEqual([
      {
        relationship: "segment_host",
        referenceId: "host-1",
        ownerIds: ["segment-1", "segment-2"],
      },
    ]);
  });

  it("joins attachment anchors to graph nodes and edges", () => {
    const graph = graphContract(
      [
        segmentNode("segment-1"),
        hostNode("host-1"),
        serviceNode("service-1"),
        vulnerabilityNode("vulnerability-1"),
        credentialNode("credential-1"),
        missionCapabilityNode("capability-1"),
      ],
      [
        hasVulnerabilityEdge(
          "has-vulnerability-1",
          "service-1",
          "vulnerability-1",
        ),
        authenticatesToEdge("authenticates-to-1", "credential-1", "host-1"),
        supportsEdge("supports-1", "service-1", "capability-1"),
      ],
    );
    const projection = projectionOf({
      segments: [segmentRecord("segment-1", ["host-1"])],
      hosts: [hostRecord("host-1", "segment-1", [], 3)],
      services: [serviceRecord("service-1", "host-1")],
      attachments: [
        attachmentRecord("vulnerability-1", "Vulnerability", [
          anchorRecord("service-1", "has-vulnerability-1", "HasVulnerability"),
        ]),
        attachmentRecord("credential-1", "Credential", [
          anchorRecord("host-1", "authenticates-to-1", "AuthenticatesTo"),
        ]),
        attachmentRecord("capability-1", "MissionCapability", [
          anchorRecord("service-1", "supports-1", "Supports"),
        ]),
      ],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.attachments.map((attachment) => attachment.id)).toEqual([
      "capability-1",
      "credential-1",
      "vulnerability-1",
    ]);
    const vulnerability = scene.attachments[2]!;
    expect(vulnerability.node.type).toBe("Vulnerability");
    expect(vulnerability.anchors[0]!.node.id).toBe("service-1");
    expect(vulnerability.anchors[0]!.edge.id).toBe("has-vulnerability-1");
    expect(vulnerability.anchors[0]!.anchor.relationship_type).toBe(
      "HasVulnerability",
    );
    expect(scene.unplaced).toEqual([]);
  });

  it("validates attachment anchors and leaves unsupported anchors out", () => {
    const graph = graphContract([vulnerabilityNode("vulnerability-1")]);
    const projection = projectionOf({
      attachments: [
        attachmentRecord("vulnerability-1", "Vulnerability", [
          anchorRecord("host-ghost", "edge-ghost", "HasVulnerability"),
        ]),
      ],
      issues: [issueRecord("context_without_anchor", "vulnerability-1")],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.attachments[0]!.anchors).toEqual([]);
    expect(
      scene.unplaced.map((entry) => [
        entry.status,
        entry.missing?.relationship,
        entry.missing?.referenceId,
      ]),
    ).toEqual([
      ["placement_issue", undefined, undefined],
      ["missing_reference", "anchor_edge", "edge-ghost"],
      ["missing_reference", "anchor_node", "host-ghost"],
    ]);
  });

  it("rejects an attachment whose node type contradicts the projection", () => {
    const graph = graphContract([
      credentialNode("credential-1"),
      vulnerabilityNode("vulnerability-1"),
    ]);
    const projection = projectionOf({
      attachments: [
        attachmentRecord("credential-1", "Vulnerability", []),
        attachmentRecord("vulnerability-1", "Vulnerability", []),
      ],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.attachments.map((attachment) => attachment.id)).toEqual([
      "vulnerability-1",
    ]);
    expect(
      scene.unplaced.map((entry) => [
        entry.status,
        entry.entityId,
        entry.missing?.relationship,
      ]),
    ).toEqual([
      ["no_placement", "vulnerability-1", undefined],
      ["missing_reference", "credential-1", "attachment_type"],
    ]);
  });

  it("joins policy groups to segment scenes and reachability edges", () => {
    const graph = graphContract(
      [
        segmentNode("segment-1"),
        segmentNode("segment-2"),
        segmentNode("segment-3"),
      ],
      [
        reachabilityEdge("reachability-1", "segment-1", "segment-2"),
        reachabilityEdge("reachability-2", "segment-1", "segment-2"),
      ],
    );
    const projection = projectionOf({
      segments: [
        segmentRecord("segment-1"),
        segmentRecord("segment-2"),
        segmentRecord("segment-3"),
      ],
      policy_groups: [
        policyGroupRecord("segment-1", "segment-2", [
          "reachability-1",
          "reachability-2",
        ]),
        policyGroupRecord("segment-1", "segment-3", ["reachability-missing"]),
        policyGroupRecord("segment-2", "segment-ghost", []),
      ],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.policyGroups).toHaveLength(2);
    expect(scene.policyGroups[0]!.from.id).toBe("segment-1");
    expect(scene.policyGroups[0]!.to.id).toBe("segment-2");
    expect(scene.policyGroups[0]!.edges.map((edge) => edge.id)).toEqual([
      "reachability-1",
      "reachability-2",
    ]);
    expect(scene.policyGroups[1]!.edges).toEqual([]);
    expect(
      scene.unplaced.map((entry) => [
        entry.missing?.relationship,
        entry.missing?.referenceId,
      ]),
    ).toEqual([
      ["policy_edge", "reachability-missing"],
      ["policy_segment", "segment-ghost"],
    ]);
  });

  it("joins flow groups to host and service scenes", () => {
    const graph = graphContract([
      segmentNode("segment-1"),
      hostNode("host-1"),
      hostNode("host-2"),
      serviceNode("service-1"),
      serviceNode("service-2"),
    ]);
    const projection = projectionOf({
      segments: [segmentRecord("segment-1", ["host-1", "host-2"])],
      hosts: [
        hostRecord("host-1", "segment-1"),
        hostRecord("host-2", "segment-1"),
      ],
      services: [
        serviceRecord("service-1", "host-2"),
        serviceRecord("service-2", "host-2"),
      ],
      flow_groups: [
        flowGroupRecord(
          "host-1",
          "host-2",
          ["service-1", "service-missing"],
          ["flow-1", "flow-2"],
        ),
        flowGroupRecord("host-1", "host-ghost", ["service-1"], ["flow-3"]),
      ],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(scene.flowGroups).toHaveLength(1);
    expect(scene.flowGroups[0]!.source.id).toBe("host-1");
    expect(scene.flowGroups[0]!.target.id).toBe("host-2");
    expect(scene.flowGroups[0]!.services.map((service) => service.id)).toEqual([
      "service-1",
    ]);
    expect(scene.flowGroups[0]!.flowIds).toEqual(["flow-1", "flow-2"]);
    expect(
      scene.unplaced.map((entry) => [
        entry.missing?.relationship,
        entry.missing?.referenceId,
      ]),
    ).toEqual([
      ["flow_host", "host-ghost"],
      ["flow_service", "service-missing"],
    ]);
  });

  it("surfaces pending graph edges in the Unplaced output", () => {
    const graph = graphContract(
      [segmentNode("segment-1"), hostNode("host-1")],
      [reachabilityEdge("reachability-1", "segment-1", "segment-1")],
    );
    const projection = projectionOf({
      segments: [segmentRecord("segment-1", ["host-1"])],
      hosts: [hostRecord("host-1", "segment-1")],
    });

    const scene = buildTopologyScene(graph, projection, {
      pendingEntityIds: ["reachability-1"],
    });

    const entry = scene.unplaced.find(
      (item) => item.entityId === "reachability-1",
    )!;
    expect(entry.status).toBe("pending");
    expect(entry.node).toBeNull();
    expect(entry.edge?.id).toBe("reachability-1");
    expect(entry.edge?.type).toBe("SegmentReachability");
  });

  it("lists entities changed after the projection as pending", () => {
    const graph = graphContract([hostNode("host-1"), hostNode("host-2")]);
    const projection = projectionOf({
      hosts: [hostRecord("host-1")],
      issues: [issueRecord("host_without_segment", "host-1")],
    });

    const scene = buildTopologyScene(graph, projection, {
      pendingEntityIds: ["host-1", "host-2", "edge-1"],
    });

    expect(
      scene.unplaced.map((entry) => [entry.entityId, entry.status]),
    ).toEqual([
      ["host-1", "placement_issue"],
      ["host-2", "pending"],
    ]);
    expect(scene.unplaced[1]!.node?.id).toBe("host-2");
    expect(scene.unplaced[1]!.issue).toBeNull();
  });

  it("produces the same scene for shuffled input", () => {
    const graph = graphContract(
      [
        segmentNode("segment-1"),
        segmentNode("segment-2"),
        hostNode("host-1"),
        hostNode("host-2"),
        hostNode("host-orphan"),
        serviceNode("service-1"),
        serviceNode("service-orphan"),
        vulnerabilityNode("vulnerability-1"),
      ],
      [
        reachabilityEdge("reachability-1", "segment-1", "segment-2"),
        hasVulnerabilityEdge(
          "has-vulnerability-1",
          "service-1",
          "vulnerability-1",
        ),
      ],
    );
    const projection = projectionOf({
      segments: [
        segmentRecord("segment-2"),
        segmentRecord("segment-1", ["host-2", "host-1"], { service_count: 1 }),
      ],
      hosts: [
        hostRecord("host-2", "segment-1"),
        hostRecord("host-1", "segment-1", ["service-1"]),
        hostRecord("host-orphan", null, ["service-orphan"]),
      ],
      services: [
        serviceRecord("service-1", "host-1"),
        serviceRecord("service-orphan", "host-orphan"),
      ],
      attachments: [
        attachmentRecord("vulnerability-1", "Vulnerability", [
          anchorRecord("service-1", "has-vulnerability-1", "HasVulnerability"),
        ]),
      ],
      policy_groups: [
        policyGroupRecord("segment-1", "segment-2", ["reachability-1"]),
      ],
      flow_groups: [
        flowGroupRecord("host-1", "host-2", ["service-1"], ["flow-1"]),
      ],
    });

    const scene = buildTopologyScene(graph, projection);
    const shuffled = buildTopologyScene(
      graphContract([...graph.nodes].reverse(), [...graph.edges].reverse()),
      projectionOf({
        segments: [...projection.segments].reverse(),
        hosts: [...projection.hosts].reverse(),
        services: [...projection.services].reverse(),
        attachments: [...projection.attachments].reverse(),
        policy_groups: [...projection.policy_groups].reverse(),
        flow_groups: [...projection.flow_groups].reverse(),
        issues: [...projection.issues].reverse(),
      }),
    );

    expect(JSON.stringify(shuffled)).toBe(JSON.stringify(scene));
  });

  it("does not mutate its inputs or call the network", () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const graph = graphContract([segmentNode("segment-1"), hostNode("host-1")]);
    const projection = projectionOf({
      segments: [segmentRecord("segment-1", ["host-1"])],
      hosts: [hostRecord("host-1", "segment-1")],
    });
    const graphBefore = structuredClone(graph);
    const projectionBefore = structuredClone(projection);

    buildTopologyScene(graph, projection, { pendingEntityIds: ["host-1"] });

    expect(graph).toEqual(graphBefore);
    expect(projection).toEqual(projectionBefore);
    expect(fetchSpy).not.toHaveBeenCalled();
    fetchSpy.mockRestore();
  });

  it("offers a selection only for an Unplaced entity the graph contains", () => {
    const graph = graphContract(
      [segmentNode("segment-1"), hostNode("host-1")],
      [containsEdge("contains-1", "segment-1", "host-1")],
    );
    const projection = projectionOf({
      segments: [segmentRecord("segment-1", ["host-1", "host-ghost"])],
      hosts: [hostRecord("host-1", "segment-1")],
      issues: [issueRecord("host_without_segment", "host-1")],
    });
    const scene = buildTopologyScene(graph, projection, {
      pendingEntityIds: ["contains-1"],
    });
    const selectionOf = (entityId: string) =>
      unplacedSelection(scene.unplaced.find((e) => e.entityId === entityId)!);

    // An unplaced entity and a pending relationship stay selectable.
    expect(selectionOf("host-1")).toEqual({ kind: "node", id: "host-1" });
    expect(selectionOf("contains-1")).toEqual({
      kind: "edge",
      id: "contains-1",
    });
    // A reference the graph does not contain is never selectable.
    expect(selectionOf("host-ghost")).toBeNull();
  });
});
