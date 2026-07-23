import { describe, it, expect } from "vitest";
import { nodeStyleFor, type NodeStyle } from "../nodeStyleMappings";
import type { Node } from "../../../contract";

const nodeTypes = ["Host", "Service", "Vulnerability"] as const;

describe("nodeStyleMappings", () => {
  nodeTypes.forEach((type) => {
    it(`defines a complete style for ${type}`, () => {
      const node = { type } as Node;
      const style = nodeStyleFor(node);

      expect(style).not.toBeNull();
      expect(style!.color).toBeTruthy();
      expect(style!.component).toBeDefined();
    });
  });

  it("returns null for an unknown node type", () => {
    const node = { type: "UnknownType" } as unknown as Node;
    expect(nodeStyleFor(node)).toBeNull();
  });
});
