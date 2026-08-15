import { describe, expect, it } from "vitest";
import type { LoadedGraph } from "../../contract";
import { arrangeNetwork } from "./NetworkCanvasLayout";

function graph(): LoadedGraph {
  return {
    id: "graph",
    title: "Network",
    nodes: [
      {
        id: "zone",
        type: "NetworkSegment",
        data: { name: "DMZ", cidr: null },
        view_data: { x_pos: 0, y_pos: 0 },
      },
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
        view_data: { x_pos: 0, y_pos: 0 },
      },
    ],
    edges: [
      {
        id: "contains-a",
        type: "Contains",
        from_id: "zone",
        to_id: "host-a",
        data: {},
      },
      {
        id: "contains-b",
        type: "Contains",
        from_id: "zone",
        to_id: "host-b",
        data: {},
      },
    ],
  };
}

describe("arrangeNetwork", () => {
  it("returns persisted positions without mutating the original graph", () => {
    const input = graph();
    const arranged = arrangeNetwork(input);

    expect(input.nodes.map((node) => node.view_data)).toEqual([
      { x_pos: 0, y_pos: 0 },
      { x_pos: 0, y_pos: 0 },
      { x_pos: 0, y_pos: 0 },
    ]);
    const [first, second] = arranged.nodes.filter(
      (node) => node.type === "Host",
    );
    expect(
      Math.hypot(
        first!.view_data.x_pos - second!.view_data.x_pos,
        first!.view_data.y_pos - second!.view_data.y_pos,
      ),
    ).toBeGreaterThan(100);
  });
});
