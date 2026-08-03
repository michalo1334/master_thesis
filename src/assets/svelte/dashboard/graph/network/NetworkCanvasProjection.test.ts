import { describe, expect, it } from "vitest";
import type { LoadedGraph } from "../../contract";
import { cullNetworkHosts, projectNetwork } from "./NetworkCanvasProjection";

function graph(): LoadedGraph {
  return {
    id: "graph",
    title: "Network",
    nodes: [
      {
        id: "host-a",
        type: "Host",
        data: { name: "A" },
        view_data: { x_pos: 0, y_pos: 0 },
      },
      {
        id: "host-b",
        type: "Host",
        data: { name: "B" },
        view_data: { x_pos: 500, y_pos: 0 },
      },
      {
        id: "segment",
        type: "NetworkSegment",
        data: { name: "DMZ", cidr: "10.0.0.0/24" },
        view_data: { x_pos: 0, y_pos: -200 },
      },
      {
        id: "segment-b",
        type: "NetworkSegment",
        data: { name: "LAN", cidr: "10.0.1.0/24" },
        view_data: { x_pos: 500, y_pos: -200 },
      },
      {
        id: "service",
        type: "Service",
        data: { name: "https", port: 443, protocol: "tcp" },
        view_data: { x_pos: 0, y_pos: 0 },
      },
      {
        id: "vulnerability",
        type: "Vulnerability",
        data: {
          identifier: "CVE-1",
          exploit_probability: 0.5,
          cvss: {} as never,
        },
        view_data: { x_pos: 0, y_pos: 0 },
      },
    ],
    edges: [
      {
        id: "runs",
        type: "Runs",
        from_id: "host-a",
        to_id: "service",
        data: {},
      },
      {
        id: "has-vulnerability",
        type: "HasVulnerability",
        from_id: "service",
        to_id: "vulnerability",
        data: { granted_privilege: "user", required_privilege: "none" },
      },
      {
        id: "reachability",
        type: "SegmentReachability",
        from_id: "segment",
        to_id: "segment-b",
        data: { protocol: "tcp" },
      },
      {
        id: "contains",
        type: "Contains",
        from_id: "segment",
        to_id: "host-a",
        data: {},
      },
      {
        id: "contains-b",
        type: "Contains",
        from_id: "segment-b",
        to_id: "host-b",
        data: {},
      },
    ],
  };
}

describe("projectNetwork", () => {
  it("folds ownership into hosts", () => {
    const projection = projectNetwork(graph());

    expect(projection.hosts[0]).toMatchObject({
      id: "host-a",
      services: [
        { node: { id: "service" }, vulnerabilities: [{ id: "vulnerability" }] },
      ],
    });
  });

  it("maps segment policy edges directly between segments", () => {
    expect(projectNetwork(graph()).segmentLinks).toEqual([
      {
        id: "segment:segment-b",
        sourceId: "segment",
        targetId: "segment-b",
        edgeIds: ["reachability"],
      },
    ]);
  });

  it("projects segment membership", () => {
    expect(projectNetwork(graph()).hosts[0].segmentId).toBe("segment");
  });

  it("culls hosts outside the transformed viewport", () => {
    const hosts = projectNetwork(graph()).hosts;

    expect(
      cullNetworkHosts(
        hosts,
        { width: 200, height: 200 },
        { x: 0, y: 0 },
        100,
      ).map((host) => host.id),
    ).toEqual(["host-a"]);
  });
});
