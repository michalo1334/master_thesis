import { describe, expect, it } from "vitest";
import { indexTopologyScene } from "../topology-scene-index";
import { NODE_HEIGHT, NODE_WIDTH } from "../canvas/geometry";
import { buildTopologyFixture } from "./topology-test-fixture";
import { buildTopologySpatialView } from "./canvas-spatial-view-model";
import { CONTEXT_SIZE, measureTopology, SERVICE_SIZE } from "./layout";

const UNPLACED_CARD_HEIGHT = 46;

describe("buildTopologySpatialView", () => {
  it("keeps projected rows, frame rectangles, and authored floaters ordered", () => {
    const { scene } = buildTopologyFixture();
    const layout = measureTopology(scene);
    const view = buildTopologySpatialView(
      scene,
      indexTopologyScene(scene),
      layout,
      {
        serviceSize: SERVICE_SIZE,
        contextSize: CONTEXT_SIZE,
        unplacedCardHeight: UNPLACED_CARD_HEIGHT,
      },
    );

    expect(view.hostViews.map((row) => row.host.id)).toEqual([
      "dns-1",
      "web-1",
    ]);
    expect(view.hostViews[1]?.services.map((row) => row.scene.id)).toEqual([
      "nginx",
    ]);
    expect([...view.nodeRects.keys()]).toEqual([
      "segment-a",
      "dns-1",
      "web-1",
      "nginx",
      "depl-cred",
    ]);
    expect(view.nodeRects.get("web-1")).toEqual({
      ...layout.positions.get("web-1"),
      width: NODE_WIDTH,
      height: NODE_HEIGHT,
    });
    expect(view.nodeRects.get("segment-a")).toEqual({
      ...layout.frames.get("segment-a")!.position,
      ...layout.frames.get("segment-a")!.size,
    });
    expect(
      view.unplacedFloaters.map((floater) => floater.entry.entityId),
    ).toEqual(["host-7", "orphan-svc"]);
    expect(view.entityRects.get("host-7")).toEqual({
      x: 60,
      y: 520,
      width: NODE_WIDTH,
      height: UNPLACED_CARD_HEIGHT,
    });
  });
});
