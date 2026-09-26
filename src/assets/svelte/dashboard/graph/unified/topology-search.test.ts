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
  graphContract,
  hasVulnerabilityEdge,
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
  vulnerabilityNode,
} from "../__tests__/topology-fixtures";
import { buildTopologyScene } from "../topology-scene";
import {
  ATTACHED_CONTEXT_PATH,
  searchTopology,
  topologySearchMatchRank,
  UNPLACED_PATH,
} from "./topology-search";

function fixture(): GraphContract {
  const nodes: Node[] = [
    segmentNode("segment-a", 40, 40),
    hostNode("host-dns", 60, 140),
    hostNode("host-primary-dns", 220, 140),
    hostNode("host-web", 380, 140),
    hostNode("host-orphan", 60, 520),
    serviceNode("service-nginx", 380, 240),
    credentialNode("credential-1", 60, 420),
    vulnerabilityNode("CVE-2024-1", 420, 420),
  ];
  setSegmentName(nodes, "segment-a", "Zone A");

  const edges: Edge[] = [
    containsEdge("contains-dns", "segment-a", "host-dns"),
    containsEdge("contains-primary", "segment-a", "host-primary-dns"),
    containsEdge("contains-web", "segment-a", "host-web"),
    runsEdge("runs-nginx", "host-web", "service-nginx"),
    storesCredentialEdge("stores-1", "host-web", "credential-1"),
    hasVulnerabilityEdge("has-1", "host-web", "CVE-2024-1"),
  ];

  return graphContract(nodes, edges);
}

function setSegmentName(nodes: Node[], id: string, name: string): void {
  const node = nodes.find((entry) => entry.id === id);
  if (node?.type === "NetworkSegment") node.data = { name, cidr: null };
}

function projection() {
  return projectionOf({
    segments: [
      segmentRecord("segment-a", ["host-dns", "host-primary-dns", "host-web"], {
        service_count: 1,
        context_count: 2,
      }),
    ],
    hosts: [
      hostRecord("host-dns", "segment-a"),
      hostRecord("host-primary-dns", "segment-a"),
      hostRecord("host-web", "segment-a", ["service-nginx"], 2),
    ],
    services: [serviceRecord("service-nginx", "host-web")],
    attachments: [
      attachmentRecord("credential-1", "Credential", [
        anchorRecord("host-web", "stores-1", "StoresCredential"),
      ]),
      attachmentRecord("CVE-2024-1", "Vulnerability", [
        anchorRecord("host-web", "has-1", "HasVulnerability"),
      ]),
    ],
    issues: [issueRecord("host_without_segment", "host-orphan")],
  });
}

describe("searchTopology", () => {
  it("ranks prefix, substring, and type matches in precedence order", () => {
    const prefix = hostNode("web-host");
    const substring = hostNode("primary-web-host");
    const type = serviceNode("nginx");

    expect(topologySearchMatchRank(prefix, "web")).toBe(0);
    expect(topologySearchMatchRank(substring, "web")).toBe(1);
    expect(topologySearchMatchRank(type, "service")).toBe(2);
    expect(topologySearchMatchRank(type, "missing")).toBe(-1);
    expect(topologySearchMatchRank(type, "   ")).toBe(-1);
  });

  it("returns nothing for an empty or blank query", () => {
    const scene = buildTopologyScene(fixture(), projection());

    expect(searchTopology(scene, "")).toEqual([]);
    expect(searchTopology(scene, "   ")).toEqual([]);
  });

  it("finds a host with its segment path", () => {
    const scene = buildTopologyScene(fixture(), projection());

    const results = searchTopology(scene, "web");
    const host = results.find((entry) => entry.id === "host-web");

    expect(host).toBeDefined();
    expect(host?.label).toBe("host-web");
    expect(host?.path).toBe("Zone A / host-web");
    expect(host?.unplaced).toBe(false);
  });

  it("finds a service with its ownership path", () => {
    const scene = buildTopologyScene(fixture(), projection());

    const [result] = searchTopology(scene, "nginx");

    expect(result?.id).toBe("service-nginx");
    expect(result?.path).toBe("Zone A / host-web / service-nginx");
  });

  it("reports attached context under the attached-context path", () => {
    const scene = buildTopologyScene(fixture(), projection());

    const results = searchTopology(scene, "credential-1");

    expect(results.map((entry) => entry.id)).toContain("credential-1");
    expect(results.find((entry) => entry.id === "credential-1")?.path).toBe(
      ATTACHED_CONTEXT_PATH,
    );
  });

  it("matches a node type when the label does not contain the query", () => {
    const scene = buildTopologyScene(fixture(), projection());

    const results = searchTopology(scene, "vulnerability");

    expect(results.map((entry) => entry.id)).toEqual(["CVE-2024-1"]);
  });

  it("ranks a label prefix above a label substring", () => {
    const scene = buildTopologyScene(fixture(), projection());

    expect(searchTopology(scene, "dns").map((entry) => entry.id)).toEqual([
      "host-dns",
      "host-primary-dns",
    ]);
  });

  it("includes unplaced entities and marks them", () => {
    const scene = buildTopologyScene(fixture(), projection());

    const [result] = searchTopology(scene, "host-orphan");

    expect(result?.id).toBe("host-orphan");
    expect(result?.path).toBe(UNPLACED_PATH);
    expect(result?.unplaced).toBe(true);
  });

  it("reports a placed entity once when a pending change also lists it", () => {
    const scene = buildTopologyScene(fixture(), projection(), {
      pendingEntityIds: ["host-web"],
    });

    const results = searchTopology(scene, "web");

    expect(results.filter((entry) => entry.id === "host-web")).toHaveLength(1);
    expect(results.find((entry) => entry.id === "host-web")?.unplaced).toBe(
      false,
    );
  });

  it("limits the number of results", () => {
    const scene = buildTopologyScene(fixture(), projection());

    expect(searchTopology(scene, "dns", 1).map((entry) => entry.id)).toEqual([
      "host-dns",
    ]);
  });
});
