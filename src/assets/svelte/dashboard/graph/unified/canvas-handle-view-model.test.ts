import { describe, expect, it } from "vitest";
import { indexTopologyScene } from "../topology-scene-index";
import { buildTopologyConnectionHandles } from "./canvas-handle-view-model";
import { buildTopologySpatialView } from "./canvas-spatial-view-model";
import { CONTEXT_SIZE, measureTopology, SERVICE_SIZE } from "./layout";
import { buildTopologyFixture } from "./topology-test-fixture";

const UNPLACED_CARD_HEIGHT = 46;

function hostViews() {
  const { scene } = buildTopologyFixture();
  const layout = measureTopology(scene);
  return buildTopologySpatialView(scene, indexTopologyScene(scene), layout, {
    serviceSize: SERVICE_SIZE,
    contextSize: CONTEXT_SIZE,
    unplacedCardHeight: UNPLACED_CARD_HEIGHT,
  }).hostViews;
}

describe("buildTopologyConnectionHandles", () => {
  it("keeps disclosed host and service controls ordered with their geometry", () => {
    const views = hostViews();
    const handles = buildTopologyConnectionHandles(views, {
      detail: "medium",
      revealsHost: (entityId) => entityId === "web-1",
      revealsService: (entityId) => entityId === "nginx",
      serviceSize: { width: 118, height: 27 },
      hostGlyphHeight: 31,
    });

    expect(handles.map((handle) => handle.key)).toEqual([
      "host:web-1",
      "service:nginx",
    ]);
    expect(handles.map((handle) => handle.node.id)).toEqual(["web-1", "nginx"]);
    expect(handles.map((handle) => handle.side)).toEqual(["right", "right"]);
    expect(handles[0]).toMatchObject({
      position: views[1]!.position,
      offset: 15.5,
    });
    expect(handles[1]).toMatchObject({
      position: views[1]!.services[0]!.position,
      width: 118,
      offset: 13.5,
    });
  });

  it("uses the near-detail host offset and excludes hidden service controls", () => {
    const views = hostViews();
    const handles = buildTopologyConnectionHandles(views, {
      detail: "near",
      revealsHost: () => true,
      revealsService: () => false,
      serviceSize: { width: 90, height: 20 },
      hostGlyphHeight: 20,
    });

    expect(handles.map((handle) => handle.key)).toEqual([
      "host:dns-1",
      "host:web-1",
    ]);
    expect(handles.map((handle) => handle.offset)).toEqual([36, 36]);
  });
});
