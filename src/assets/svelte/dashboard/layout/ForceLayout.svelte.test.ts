import { describe, it, expect } from "vitest";
import { applyForceLayout } from "./ForceLayout.svelte";
import { defaultForceParams } from "./ForceLayout.types";
import type { Node, Edge } from "../contract";

type NodeType = "Host" | "Service" | "Vulnerability";

function mkNode(id: string, type: NodeType): Node {
  switch (type) {
    case "Host":
      return {
        id,
        type,
        data: { name: id },
        view_data: { x_pos: 0, y_pos: 0 },
      };
    case "Service":
      return {
        id,
        type,
        data: { name: id, protocol: "tcp", port: 80 },
        view_data: { x_pos: 0, y_pos: 0 },
      };
    case "Vulnerability":
      return {
        id,
        type,
        data: { identifier: id, cvss_score: 0, exploit_probability: 0 },
        view_data: { x_pos: 0, y_pos: 0 },
      };
  }
}

function groupByType(nodes: Node[]): Map<string, Node[]> {
  const map = new Map<string, Node[]>();
  for (const n of nodes) {
    const group = map.get(n.type) ?? [];
    group.push(n);
    map.set(n.type, group);
  }
  return map;
}

function avg(nodes: Node[], key: "x_pos" | "y_pos"): number {
  return nodes.reduce((s, n) => s + n.view_data[key], 0) / nodes.length;
}

function dist(
  a: { x: number; y: number },
  b: { x: number; y: number },
): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

describe("applyForceLayout type clustering", () => {
  it("separates nodes of different types into distinct clusters", () => {
    const nodes: Node[] = [
      mkNode("h1", "Host"),
      mkNode("h2", "Host"),
      mkNode("s1", "Service"),
      mkNode("s2", "Service"),
      mkNode("v1", "Vulnerability"),
      mkNode("v2", "Vulnerability"),
    ];
    const edges: Edge[] = [
      {
        id: "e1",
        from_id: "h1",
        to_id: "s1",
        type: "Runs",
        data: {},
      },
      {
        id: "e2",
        from_id: "s1",
        to_id: "v1",
        type: "HasVulnerability",
        data: {},
      },
    ];

    applyForceLayout(nodes, edges, defaultForceParams);

    const groups = groupByType(nodes);
    const hosts = groups.get("Host")!;
    const services = groups.get("Service")!;
    const vulns = groups.get("Vulnerability")!;

    // Verify all nodes got finite positions.
    for (const n of nodes) {
      expect(Number.isFinite(n.view_data.x_pos)).toBe(true);
      expect(Number.isFinite(n.view_data.y_pos)).toBe(true);
    }

    // Cluster centers should be distinctly separated — with
    // anchor radius=3*linkDistance, centroids are far apart.
    const hCenter = { x: avg(hosts, "x_pos"), y: avg(hosts, "y_pos") };
    const sCenter = { x: avg(services, "x_pos"), y: avg(services, "y_pos") };
    const vCenter = { x: avg(vulns, "x_pos"), y: avg(vulns, "y_pos") };

    const dHS = dist(hCenter, sCenter);
    const dHV = dist(hCenter, vCenter);
    const dSV = dist(sCenter, vCenter);

    expect(dHS).toBeGreaterThan(defaultForceParams.linkDistance * 2);
    expect(dHV).toBeGreaterThan(defaultForceParams.linkDistance * 2);
    expect(dSV).toBeGreaterThan(defaultForceParams.linkDistance * 2);

    // Same-type nodes must be materially tighter than every inter-type
    // centroid gap — intra-cluster cohesion must exceed inter-cluster spacing.
    function nodeSpread(nodes: Node[]): number {
      return dist(
        { x: nodes[0].view_data.x_pos, y: nodes[0].view_data.y_pos },
        { x: nodes[1].view_data.x_pos, y: nodes[1].view_data.y_pos },
      );
    }

    const hostSpread = nodeSpread(hosts);
    const svcSpread = nodeSpread(services);
    const vulnSpread = nodeSpread(vulns);

    for (const intraSpread of [hostSpread, svcSpread, vulnSpread]) {
      expect(intraSpread).toBeLessThan(dHS);
      expect(intraSpread).toBeLessThan(dHV);
      expect(intraSpread).toBeLessThan(dSV);
    }
  });

  it("handles a single type without errors", () => {
    const nodes: Node[] = [
      mkNode("a", "Host"),
      mkNode("b", "Host"),
      mkNode("c", "Host"),
    ];
    const edges: Edge[] = [
      {
        id: "e1",
        from_id: "a",
        to_id: "b",
        type: "Runs",
        data: {},
      },
    ];

    applyForceLayout(nodes, edges, defaultForceParams);

    for (const n of nodes) {
      expect(Number.isFinite(n.view_data.x_pos)).toBe(true);
      expect(Number.isFinite(n.view_data.y_pos)).toBe(true);
    }
  });

  it("returns immediately for empty node list", () => {
    const nodes: Node[] = [];
    const edges: Edge[] = [];
    // Should not throw.
    expect(() =>
      applyForceLayout(nodes, edges, defaultForceParams),
    ).not.toThrow();
  });
});
