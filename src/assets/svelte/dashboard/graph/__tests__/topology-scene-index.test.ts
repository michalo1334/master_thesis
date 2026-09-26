import { describe, expect, it } from "vitest";
import {
  graphContract,
  hostNode,
  hostRecord,
  projectionOf,
  segmentNode,
  segmentRecord,
  serviceNode,
  serviceRecord,
} from "./topology-fixtures";
import { indexTopologyScene } from "../topology-scene-index";
import { buildTopologyScene } from "../topology-scene";

describe("indexTopologyScene", () => {
  it("preserves scene order and projected parent links", () => {
    const scene = buildTopologyScene(
      graphContract([
        segmentNode("segment-2"),
        segmentNode("segment-1"),
        hostNode("host-2"),
        hostNode("host-1"),
        hostNode("host-floater"),
        serviceNode("service-1"),
      ]),
      projectionOf({
        segments: [
          segmentRecord("segment-2", ["host-2"]),
          segmentRecord("segment-1", ["host-1"]),
        ],
        hosts: [
          hostRecord("host-2", "segment-2"),
          hostRecord("host-1", "segment-1", ["service-1"]),
        ],
        services: [serviceRecord("service-1", "host-1")],
      }),
    );

    const first = indexTopologyScene(scene);
    const second = indexTopologyScene(scene);

    expect(first.segments.map((entry) => entry.id)).toEqual([
      "segment-1",
      "segment-2",
    ]);
    expect(first.hosts.map((entry) => [entry.id, entry.segment.id])).toEqual([
      ["host-1", "segment-1"],
      ["host-2", "segment-2"],
    ]);
    expect(
      first.services.map((entry) => [
        entry.id,
        entry.host.id,
        entry.segment.id,
      ]),
    ).toEqual([["service-1", "host-1", "segment-1"]]);
    expect(first.projectedEntities.map((entry) => entry.id)).toEqual([
      "segment-1",
      "host-1",
      "service-1",
      "segment-2",
      "host-2",
    ]);
    expect([...first.projectedEntityIds]).toEqual([
      "segment-1",
      "host-1",
      "service-1",
      "segment-2",
      "host-2",
    ]);
    expect(first.projectedEntityIds.has("host-floater")).toBe(false);
    expect(first.nodesById.get("host-floater")?.id).toBe("host-floater");
    expect(second.projectedEntities).toEqual(first.projectedEntities);
  });
});
