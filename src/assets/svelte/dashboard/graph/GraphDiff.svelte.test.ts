import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/svelte";
import GraphDiff from "./GraphDiff.svelte";
import { GraphDiffDocument } from "./GraphDiffDocument.svelte";
import type { GraphDiffResult, LoadedGraph } from "../contract";

afterEach(cleanup);

function segmentNode(id: string, name: string, xPos: number) {
  return {
    id,
    type: "NetworkSegment" as const,
    data: { name, cidr: "10.0.0.0/24" },
    view_data: { x_pos: xPos, y_pos: 0 },
  };
}

function policyEdge(
  id: string,
  fromId: string,
  toId: string,
  data: { protocol: "tcp" | "udp"; port_start?: number; port_end?: number },
) {
  return {
    id,
    type: "SegmentReachability" as const,
    from_id: fromId,
    to_id: toId,
    data,
  };
}

function makeGraph(overrides: Partial<LoadedGraph> = {}): LoadedGraph {
  return {
    id: "g1",
    title: "Network",
    revision_id: "base-r1",
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    nodes: [],
    edges: [],
    ...overrides,
  };
}

function diffDocument(): GraphDiffDocument {
  const base = makeGraph({
    id: "base",
    title: "Base",
    revision_id: "base-r1",
    nodes: [segmentNode("seg-a", "DMZ", 0), segmentNode("seg-b", "LAN", 400)],
    edges: [
      policyEdge("policy-removed", "seg-a", "seg-b", {
        protocol: "tcp",
        port_start: 80,
        port_end: 443,
      }),
    ],
  });
  const result: GraphDiffResult = {
    graph: makeGraph({
      id: "merged",
      title: "Merged",
      nodes: [
        segmentNode("seg-a", "DMZ", 0),
        segmentNode("seg-b", "LAN", 400),
        segmentNode("seg-c", "Guest", 800),
      ],
      edges: [
        policyEdge("policy-removed", "seg-a", "seg-b", {
          protocol: "tcp",
          port_start: 80,
          port_end: 443,
        }),
        policyEdge("policy-added", "seg-b", "seg-c", { protocol: "udp" }),
      ],
    }),
    node_status: [{ id: "seg-c", status: "added" }],
    edge_status: [
      { id: "policy-removed", status: "removed" },
      { id: "policy-added", status: "added" },
    ],
    node_counts: { added: 1, removed: 0, unchanged: 2 },
    edge_counts: { added: 1, removed: 1, unchanged: 0 },
  };
  return new GraphDiffDocument(
    base,
    { revisionId: "comparison-r1", title: "Comparison" },
    result,
  );
}

describe("GraphDiff", () => {
  it("renders removed and added SegmentReachability policy edges with distinct status", () => {
    render(GraphDiff, { props: { document: diffDocument() } });

    expect(
      screen.getByText(/Edges: 1 added, 1 removed, 0 unchanged/),
    ).toBeInTheDocument();

    const removedEdge = screen.getByRole("button", {
      name: "tcp:80-443 relationship",
    });
    const addedEdge = screen.getByRole("button", {
      name: "udp relationship",
    });

    expect(removedEdge.closest(".canvas-edge")).toHaveStyle({
      "--edge-stroke": "var(--ds-color-danger)",
    });
    expect(addedEdge.closest(".canvas-edge")).toHaveStyle({
      "--edge-stroke": "var(--ds-color-positive)",
    });
  });

  it("renders the policy diff read-only: unfocusable edges, no authoring connector, no delete action", () => {
    const document = diffDocument();

    render(GraphDiff, { props: { document } });

    const removedEdge = screen.getByRole("button", {
      name: "tcp:80-443 relationship",
    });
    const addedEdge = screen.getByRole("button", {
      name: "udp relationship",
    });
    for (const edge of [removedEdge, addedEdge]) {
      expect(edge).toHaveAttribute("aria-disabled", "true");
      expect(edge).not.toHaveAttribute("tabindex");
    }
    expect(
      screen.queryByRole("button", {
        name: "Create connection from NetworkSegment",
      }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("menuitem", { name: "Delete" }),
    ).not.toBeInTheDocument();
  });
});
