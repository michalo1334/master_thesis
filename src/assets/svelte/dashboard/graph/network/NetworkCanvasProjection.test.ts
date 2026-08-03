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
        type: "NetworkReachability",
        from_id: "host-b",
        to_id: "service",
        data: { protocol: "tcp" },
      },
      {
        id: "contains",
        type: "Contains",
        from_id: "segment",
        to_id: "host-a",
        data: {},
      },
    ],
  };
}

describe("projectNetwork", () => {
  it("folds ownership and collapses reachability to hosts", () => {
    const projection = projectNetwork(graph());

    expect(projection.hosts[0]).toMatchObject({
      id: "host-a",
      services: [
        { node: { id: "service" }, vulnerabilities: [{ id: "vulnerability" }] },
      ],
    });
    expect(projection.links).toEqual([
      {
        id: "host-b:host-a",
        sourceId: "host-b",
        targetId: "host-a",
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
