import { describe, expect, it } from "vitest";
import type { LoadedGraph } from "../../contract";
import { projectNetwork } from "./NetworkCanvasProjection";

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
});

function flowGraph(): LoadedGraph {
  return {
    ...graph(),
    nodes: [
      ...graph().nodes,
      {
        id: "service-b",
        type: "Service",
        data: { name: "postgres", port: 5432, protocol: "tcp" },
        view_data: { x_pos: 500, y_pos: 0 },
      },
      {
        id: "orphan-service",
        type: "Service",
        data: { name: "orphan", port: 8080, protocol: "tcp" },
        view_data: { x_pos: 250, y_pos: 100 },
      },
    ],
    edges: [
      ...graph().edges,
      {
        id: "runs-b",
        type: "Runs",
        from_id: "host-b",
        to_id: "service-b",
        data: {},
      },
    ],
  };
}

describe("projectNetwork operational flows", () => {
  it("has no operational flows without a server projection", () => {
    expect(projectNetwork(flowGraph()).operationalFlows).toEqual([]);
  });

  it("combines server flows between valid hosts and services", () => {
    const projection = projectNetwork(flowGraph(), [
      { id: "flow-1", from_id: "host-a", to_id: "service" },
      { id: "flow-2", from_id: "host-b", to_id: "service-b" },
    ]);

    expect(projection.operationalFlows).toEqual([
      expect.objectContaining({
        id: "flow-1",
        sourceId: "host-a",
        targetId: "host-a",
        serviceId: "service",
        serviceName: "https",
      }),
      expect.objectContaining({
        id: "flow-2",
        sourceId: "host-b",
        targetId: "host-b",
        serviceId: "service-b",
        serviceName: "postgres",
      }),
    ]);
  });

  it("resolves the flow target to the host running the service", () => {
    const projection = projectNetwork(flowGraph(), [
      { id: "cross", from_id: "host-a", to_id: "service-b" },
    ]);

    expect(projection.operationalFlows).toEqual([
      expect.objectContaining({ id: "cross", targetId: "host-b" }),
    ]);
  });

  it("ignores flows with unknown or unhosted endpoints", () => {
    const projection = projectNetwork(flowGraph(), [
      { id: "unknown-host", from_id: "missing-host", to_id: "service" },
      { id: "unknown-service", from_id: "host-a", to_id: "missing-service" },
      { id: "unhosted-service", from_id: "host-a", to_id: "orphan-service" },
    ]);

    expect(projection.operationalFlows).toEqual([]);
  });
});
