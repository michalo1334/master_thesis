import type { Edge, Node } from "../../../../contracts.generated/graph";
import { describe, it, expect } from "vitest";
import { nodePresentation, edgePresentation, inspectorFor } from "../registry";
const nodeTypes = [
  "Host",
  "Service",
  "Vulnerability",
  "Credential",
  "NetworkSegment",
  "MissionCapability",
] as const;
const edgeTypes = [
  "Runs",
  "SegmentReachability",
  "HasVulnerability",
  "StoresCredential",
  "AuthenticatesTo",
  "Contains",
  "Supports",
] as const;

describe("presentation registry", () => {
  describe("nodePresentation", () => {
    nodeTypes.forEach((type) => {
      it(`defines a complete presentation for ${type}`, () => {
        const pres = nodePresentation(type);

        expect(pres).not.toBeNull();
        expect(pres!.color).toBeTruthy();
        expect(pres!.glyph).toBeDefined();
        expect(pres!.info).toBeDefined();
        expect(pres!.inspector).toBeDefined();
      });
    });

    it("returns null for an unknown node type", () => {
      expect(nodePresentation("UnknownType" as Node["type"])).toBeNull();
    });
  });

  describe("edgePresentation", () => {
    edgeTypes.forEach((type) => {
      it(`defines a complete presentation for ${type}`, () => {
        const pres = edgePresentation(type);

        expect(pres).not.toBeNull();
        expect(pres!.color).toBeTruthy();
        expect(
          pres!.dashArray === null || typeof pres!.dashArray === "string",
        ).toBe(true);
        expect(pres!.inspector).toBeDefined();
      });
    });

    it("Runs edge has solid line (null dashArray)", () => {
      const pres = edgePresentation("Runs");
      expect(pres!.dashArray).toBeNull();
    });

    it("SegmentReachability presents a dashed policy edge with a label", () => {
      const pres = edgePresentation("SegmentReachability");

      expect(pres!.dashArray).toBe("5 3");

      const base = { id: "r", from_id: "segment-a", to_id: "segment-b" };
      const protocolOnly = pres!.label?.({
        ...base,
        type: "SegmentReachability",
        data: { protocol: "tcp" },
      } as Edge);
      const withPorts = pres!.label?.({
        ...base,
        type: "SegmentReachability",
        data: { protocol: "tcp", port_start: 80, port_end: 443 },
      } as Edge);

      expect(protocolOnly).toBe("tcp");
      expect(withPorts).toBe("tcp:80-443");
    });

    it("returns null for an unknown edge type", () => {
      expect(edgePresentation("UnknownType" as Edge["type"])).toBeNull();
    });
  });

  describe("inspectorFor", () => {
    const allTypes = [...nodeTypes, ...edgeTypes] as const;

    allTypes.forEach((type) => {
      it(`returns an inspector for ${type}`, () => {
        const component = inspectorFor({ type } as Node | Edge);
        expect(component).toBeDefined();
      });
    });

    it("returns EmptyInspector for undefined selectable", () => {
      const component = inspectorFor(undefined);
      expect(component).toBeDefined();
    });

    it("returns EmptyInspector for unknown type", () => {
      const component = inspectorFor({
        type: "UnknownType",
      } as unknown as Node);
      expect(component).toBeDefined();
    });
  });
});
