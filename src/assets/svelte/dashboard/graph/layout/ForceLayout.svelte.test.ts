import { describe, it, expect } from "vitest";
import { applyForceLayout, resolveOwnership } from "./ForceLayout.svelte";
import { defaultForceParams } from "./ForceLayout.types";
import type { Node, Edge } from "../../contract";

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

function mkEdge(
  id: string,
  from_id: string,
  to_id: string,
  type: Edge["type"],
): Edge {
  return { id, from_id, to_id, type, data: {} } as Edge;
}

function distance(a: Node, b: Node): number {
  return Math.hypot(
    a.view_data.x_pos - b.view_data.x_pos,
    a.view_data.y_pos - b.view_data.y_pos,
  );
}

describe("resolveOwnership", () => {
  it("resolves nested ownership from valid typed edges", () => {
    const nodes: Node[] = [
      mkNode("h1", "Host"),
      mkNode("s1", "Service"),
      mkNode("v1", "Vulnerability"),
    ];
    const edges: Edge[] = [
      mkEdge("runs", "h1", "s1", "Runs"),
      mkEdge("has-vulnerability", "s1", "v1", "HasVulnerability"),
    ];

    expect(Object.fromEntries(resolveOwnership(nodes, edges))).toEqual({
      s1: "h1",
      v1: "s1",
    });
  });

  it("ignores malformed, dangling, ambiguous, and orphan ownership edges", () => {
    const nodes: Node[] = [
      mkNode("h1", "Host"),
      mkNode("h2", "Host"),
      mkNode("s1", "Service"),
      mkNode("s-ambiguous", "Service"),
      mkNode("s-orphan", "Service"),
      mkNode("v1", "Vulnerability"),
      mkNode("v2", "Vulnerability"),
      mkNode("v-orphan", "Vulnerability"),
    ];
    const edges: Edge[] = [
      mkEdge("runs", "h1", "s1", "Runs"),
      mkEdge("has-vulnerability", "s1", "v1", "HasVulnerability"),
      mkEdge("ambiguous-first", "h1", "s-ambiguous", "Runs"),
      mkEdge("ambiguous-second", "h2", "s-ambiguous", "Runs"),
      mkEdge("malformed-runs", "s1", "v2", "Runs"),
      mkEdge("malformed-vulnerability", "h1", "v2", "HasVulnerability"),
      mkEdge("dangling", "missing-service", "v2", "HasVulnerability"),
    ];

    expect(Object.fromEntries(resolveOwnership(nodes, edges))).toEqual({
      s1: "h1",
      v1: "s1",
    });

    expect(() =>
      applyForceLayout(nodes, edges, defaultForceParams),
    ).not.toThrow();
  });

  it("returns no ownership and does not lay out empty input", () => {
    const nodes: Node[] = [];
    const edges: Edge[] = [];

    expect(Object.fromEntries(resolveOwnership(nodes, edges))).toEqual({});
    expect(() =>
      applyForceLayout(nodes, edges, defaultForceParams),
    ).not.toThrow();
  });
});

describe("applyForceLayout ownership clustering", () => {
  it("keeps services and vulnerabilities with their owners", () => {
    const h1 = mkNode("h1", "Host");
    const h2 = mkNode("h2", "Host");
    const s1 = mkNode("s1", "Service");
    const s2 = mkNode("s2", "Service");
    const v1 = mkNode("v1", "Vulnerability");
    const v2 = mkNode("v2", "Vulnerability");
    const nodes = [h1, h2, s1, s2, v1, v2];
    const edges: Edge[] = [
      mkEdge("runs-1", "h1", "s1", "Runs"),
      mkEdge("runs-2", "h2", "s2", "Runs"),
      mkEdge("vulnerability-1", "s1", "v1", "HasVulnerability"),
      mkEdge("vulnerability-2", "s2", "v2", "HasVulnerability"),
      mkEdge("reachability", "h1", "s2", "NetworkReachability"),
    ];

    applyForceLayout(nodes, edges, defaultForceParams);

    for (const node of nodes) {
      expect(Number.isFinite(node.view_data.x_pos)).toBe(true);
      expect(Number.isFinite(node.view_data.y_pos)).toBe(true);
    }

    expect(distance(s1, h1)).toBeLessThan(distance(s1, h2));
    expect(distance(s2, h2)).toBeLessThan(distance(s2, h1));
    expect(distance(v1, s1)).toBeLessThan(distance(v1, s2));
    expect(distance(v2, s2)).toBeLessThan(distance(v2, s1));
  });
});
