import { describe, it, expect } from "vitest";
import { edgeStyleFor } from "../edgeStyleMappings";
import type { Edge } from "../../../contract";

const edgeTypes = ["Runs", "NetworkReachability", "HasVulnerability"] as const;

describe("edgeStyleMappings", () => {
  edgeTypes.forEach((type) => {
    it(`defines a complete style for ${type}`, () => {
      const edge = { type } as Edge;
      const style = edgeStyleFor(edge);

      expect(style).not.toBeNull();
      expect(style!.color).toBeTruthy();
      expect(
        style!.dashArray === null || typeof style!.dashArray === "string",
      ).toBe(true);
    });
  });

  it("Runs edge has solid line (null dashArray)", () => {
    const style = edgeStyleFor({ type: "Runs" } as Edge);
    expect(style!.dashArray).toBeNull();
  });

  it("returns null for an unknown edge type", () => {
    const edge = { type: "UnknownType" } as unknown as Edge;
    expect(edgeStyleFor(edge)).toBeNull();
  });
});
