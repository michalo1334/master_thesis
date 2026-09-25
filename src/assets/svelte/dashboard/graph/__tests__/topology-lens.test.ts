import { describe, expect, it } from "vitest";
import type { GraphContract } from "../../../contracts.generated/graph";
import { buildTopologyScene, type TopologyScene } from "../topology-scene";
import {
  computeTopologyLens,
  flowGroupKey,
  policyGroupKey,
} from "../topology-lens";
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
} from "./topology-fixtures";

interface Fixture {
  graph: GraphContract;
  scene: TopologyScene;
}

/**
 * Two segments, one orphan host, one policy edge, and one flow group.
 *
 * Values are structurally similar to the canvas fixture and never reuse its
 * identifiers.
 */
function fixture(): Fixture {
  const graph = graphContract(
    [
      segmentNode("zone-north"),
      segmentNode("zone-south"),
      hostNode("north-1"),
      hostNode("north-2"),
      hostNode("south-1"),
      hostNode("orphan-1"),
      serviceNode("north-service"),
      serviceNode("south-service"),
      vulnerabilityNode("vulnerability-1"),
      credentialNode("credential-1"),
    ],
    [
      containsEdge("contains-north-1", "zone-north", "north-1"),
      containsEdge("contains-north-2", "zone-north", "north-2"),
      containsEdge("contains-south-1", "zone-south", "south-1"),
      runsEdge("runs-north", "north-1", "north-service"),
      runsEdge("runs-south", "south-1", "south-service"),
      hasVulnerabilityEdge("has-vulnerability-1", "north-1", "vulnerability-1"),
      storesCredentialEdge("stores-credential-1", "south-1", "credential-1"),
      reachabilityEdge("policy-north-south", "zone-north", "zone-south"),
    ],
  );

  const projection = projectionOf({
    segments: [
      segmentRecord("zone-north", ["north-1", "north-2"], {
        service_count: 1,
        context_count: 1,
      }),
      segmentRecord("zone-south", ["south-1"], { service_count: 1 }),
    ],
    hosts: [
      hostRecord("north-1", "zone-north", ["north-service"], 1),
      hostRecord("north-2", "zone-north"),
      hostRecord("south-1", "zone-south", ["south-service"], 1),
    ],
    services: [
      serviceRecord("north-service", "north-1"),
      serviceRecord("south-service", "south-1"),
    ],
    attachments: [
      attachmentRecord("vulnerability-1", "Vulnerability", [
        anchorRecord("north-1", "has-vulnerability-1", "HasVulnerability"),
      ]),
      attachmentRecord("credential-1", "Credential", [
        anchorRecord("south-1", "stores-credential-1", "StoresCredential"),
      ]),
    ],
    policy_groups: [
      policyGroupRecord("zone-north", "zone-south", ["policy-north-south"]),
    ],
    flow_groups: [
      flowGroupRecord("north-1", "south-1", ["south-service"], ["flow-1"]),
    ],
  });

  return { graph, scene: buildTopologyScene(graph, projection) };
}

describe("computeTopologyLens", () => {
  it("stays inactive without a focus entity", () => {
    const { graph, scene } = fixture();
    const lens = computeTopologyLens(graph, scene, []);

    expect(lens.active).toBe(false);
    expect(lens.focusIds).toEqual([]);
    expect([...lens.visibleIds]).toEqual([]);
  });

  it("reveals a focused segment with its members and context", () => {
    const { graph, scene } = fixture();
    const lens = computeTopologyLens(graph, scene, ["zone-north"]);

    expect(lens.active).toBe(true);
    expect(lens.focusIds).toEqual(["zone-north"]);
    expect([...lens.visibleIds].sort()).toEqual([
      "north-1",
      "north-2",
      "north-service",
      "vulnerability-1",
      "zone-north",
    ]);
    expect([...lens.structuralEdgeIds].sort()).toEqual([
      "contains-north-1",
      "contains-north-2",
      "runs-north",
    ]);
    expect([...lens.policyKeys]).toEqual(["zone-north:zone-south"]);
    expect([...lens.flowKeys]).toEqual(["north-1:south-1:south-service"]);
  });

  it("reveals the segment and siblings of a focused host", () => {
    const { graph, scene } = fixture();
    const lens = computeTopologyLens(graph, scene, ["north-2"]);

    expect([...lens.visibleIds].sort()).toEqual([
      "north-1",
      "north-2",
      "north-service",
      "vulnerability-1",
      "zone-north",
    ]);
    expect(lens.visibleIds.has("zone-south")).toBe(false);
    expect(lens.visibleIds.has("south-1")).toBe(false);
  });

  it("reveals the owner host of a focused service", () => {
    const { graph, scene } = fixture();
    const lens = computeTopologyLens(graph, scene, ["north-service"]);

    expect(lens.visibleIds.has("north-service")).toBe(true);
    expect(lens.visibleIds.has("north-1")).toBe(true);
    expect(lens.visibleIds.has("zone-north")).toBe(true);
    expect(lens.visibleIds.has("vulnerability-1")).toBe(true);
  });

  it("reveals the anchors of a focused context node", () => {
    const { graph, scene } = fixture();
    const lens = computeTopologyLens(graph, scene, ["credential-1"]);

    expect(lens.visibleIds.has("credential-1")).toBe(true);
    expect(lens.visibleIds.has("south-1")).toBe(true);
    expect(lens.visibleIds.has("zone-south")).toBe(true);
    expect(lens.structuralEdgeIds.has("contains-south-1")).toBe(true);
    expect(lens.visibleIds.has("zone-north")).toBe(false);
  });

  it("reveals the segment a focused flow host belongs to", () => {
    const { graph, scene } = fixture();
    const lens = computeTopologyLens(graph, scene, ["south-1"]);

    expect([...lens.flowKeys]).toEqual(["north-1:south-1:south-service"]);
    expect([...lens.policyKeys]).toEqual(["zone-north:zone-south"]);
  });

  it("ignores an entity the projection does not place", () => {
    const { graph, scene } = fixture();
    const lens = computeTopologyLens(graph, scene, ["orphan-1"]);

    expect(lens.active).toBe(false);
    expect([...lens.visibleIds]).toEqual([]);
  });

  it("keeps several focus entities and drops repeated ids", () => {
    const { graph, scene } = fixture();
    const lens = computeTopologyLens(graph, scene, [
      "zone-north",
      "credential-1",
      "zone-north",
    ]);

    expect(lens.focusIds).toEqual(["zone-north", "credential-1"]);
    expect(lens.visibleIds.has("credential-1")).toBe(true);
    expect(lens.visibleIds.has("north-1")).toBe(true);
  });

  it("keys grouped relationships by endpoints and services", () => {
    const { scene } = fixture();
    expect(policyGroupKey(scene.policyGroups[0]!)).toBe(
      "zone-north:zone-south",
    );
    expect(flowGroupKey(scene.flowGroups[0]!)).toBe(
      "north-1:south-1:south-service",
    );
  });
});
