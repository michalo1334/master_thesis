import { describe, expect, it } from "vitest";
import { buildTopologyScene } from "../topology-scene";
import {
  topologyPlacement,
  unplacedReason,
  unplacedReasonCode,
} from "../topology-placement";
import {
  containsEdge,
  graphContract,
  hostNode,
  hostRecord,
  issueRecord,
  projectionOf,
  segmentNode,
  segmentRecord,
  serviceNode,
  serviceRecord,
} from "./topology-fixtures";

describe("topology place", () => {
  it("reports no placement for an entity the projection places", () => {
    const graph = graphContract([segmentNode("zone-1"), hostNode("host-1")]);
    const projection = projectionOf({
      segments: [segmentRecord("zone-1", ["host-1"])],
      hosts: [hostRecord("host-1", "zone-1")],
    });

    const scene = buildTopologyScene(graph, projection);

    expect(topologyPlacement(scene, "host-1")).toBeNull();
  });

  it("reports a projector issue with its typed reason", () => {
    const graph = graphContract([hostNode("host-1")]);
    const projection = projectionOf({
      issues: [issueRecord("host_without_segment", "host-1")],
    });

    const scene = buildTopologyScene(graph, projection);
    const placement = topologyPlacement(scene, "host-1");

    expect(placement?.status).toBe("placement_issue");
    expect(placement?.reasonCode).toBe("host_without_segment");
    expect(placement?.reason).toBe("no segment");
  });

  it("falls back to the entity kind when the projection places nothing", () => {
    const graph = graphContract([
      segmentNode("zone-1"),
      hostNode("host-1"),
      serviceNode("service-1"),
    ]);
    const projection = projectionOf({
      segments: [segmentRecord("zone-1", ["host-1"])],
      hosts: [hostRecord("host-1", "zone-1")],
      services: [serviceRecord("service-1", null)],
    });

    const scene = buildTopologyScene(graph, projection);
    const placement = topologyPlacement(scene, "service-1");

    expect(placement?.status).toBe("no_placement");
    expect(unplacedReason(scene.unplaced[0]!)).toBe("no host");
    expect(unplacedReasonCode(scene.unplaced[0]!)).toBe("no_placement");
  });

  it("reports a pending entity as awaiting topology update", () => {
    const graph = graphContract([segmentNode("zone-1"), hostNode("host-1")]);
    const projection = projectionOf({
      segments: [segmentRecord("zone-1", ["host-1"])],
      hosts: [hostRecord("host-1", "zone-1")],
    });

    const scene = buildTopologyScene(graph, projection, {
      pendingEntityIds: ["host-1"],
    });
    const placement = topologyPlacement(scene, "host-1");

    expect(placement?.status).toBe("pending");
    expect(placement?.reason).toBe("awaiting topology update");
    expect(placement?.reasonCode).toBe("pending");
  });

  it("reports a projection reference that fails to join", () => {
    const graph = graphContract([segmentNode("zone-1")]);
    const projection = projectionOf({
      segments: [segmentRecord("zone-1", ["host-missing"])],
    });

    const scene = buildTopologyScene(graph, projection);
    const placement = topologyPlacement(scene, "host-missing");

    expect(placement?.status).toBe("missing_reference");
    expect(placement?.reasonCode).toBe("host_node");
    expect(placement?.reason).toBe("missing host");
  });

  it("keeps a segment membership conflict machine readable", () => {
    const graph = graphContract(
      [segmentNode("zone-1"), hostNode("host-1")],
      [containsEdge("contains-1", "zone-1", "host-1")],
    );
    const projection = projectionOf({
      segments: [segmentRecord("zone-1", [])],
      hosts: [hostRecord("host-1", "zone-1")],
    });

    const scene = buildTopologyScene(graph, projection);
    const placement = topologyPlacement(scene, "host-1");

    expect(placement?.reasonCode).toBe("segment_host");
    expect(placement?.reason).toBe("segment membership mismatch");
  });
});
