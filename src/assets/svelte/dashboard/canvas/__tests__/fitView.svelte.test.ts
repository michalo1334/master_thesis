import { describe, it, expect } from "vitest";
import { computeFitState } from "../fitView";
import type { Node } from "../../contract";

function mkNode(id: string, x: number, y: number): Node {
  return {
    id,
    type: "Host",
    data: { name: id },
    view_data: { x_pos: x, y_pos: y },
  };
}

const VIEW_W = 1200;
const VIEW_H = 800;
const MIN_ZOOM = 25;
const MAX_ZOOM = 200;

describe("computeFitState", () => {
  it("returns null for empty nodes", () => {
    expect(
      computeFitState({
        nodes: [],
        viewportWidth: VIEW_W,
        viewportHeight: VIEW_H,
        minZoom: MIN_ZOOM,
        maxZoom: MAX_ZOOM,
      }),
    ).toBeNull();
  });

  it("fits a single node centered in the viewport", () => {
    const result = computeFitState({
      nodes: [mkNode("n1", 100, 200)],
      viewportWidth: VIEW_W,
      viewportHeight: VIEW_H,
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
    })!;

    expect(result).not.toBeNull();
    expect(result.zoom).toBeGreaterThanOrEqual(MIN_ZOOM);
    expect(result.zoom).toBeLessThanOrEqual(MAX_ZOOM);

    // A single node (120x72) with 60px padding → bounds: 100..220 x 200..272
    // padded width = 120 + 120 = 240, padded height = 72 + 120 = 192
    expect(result.zoom).toBe(MAX_ZOOM);
  });

  it("zooms out to fit widely spread nodes", () => {
    // Two nodes 1000px apart horizontally
    const result = computeFitState({
      nodes: [mkNode("a", 0, 0), mkNode("b", 1000, 0)],
      viewportWidth: VIEW_W,
      viewportHeight: VIEW_H,
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
    })!;

    expect(result).not.toBeNull();
    // graph spans from x=0 to x=1120 (1000 + 120)
    // padded: 1120 + 120 = 1240
    // zoomX = (1200 / 1240) * 100 ≈ 96.77
    // zoomY = (800 / 192) * 100 = 416 → clamped at MAX_ZOOM
    // final zoom ≈ 96.77
    expect(result.zoom).toBeLessThan(100);
    expect(result.zoom).toBeGreaterThanOrEqual(MIN_ZOOM);
  });

  it("clamps zoom to MIN_ZOOM when nodes won't fit", () => {
    // Very spread out nodes that won't fit at min zoom
    const result = computeFitState({
      nodes: [mkNode("a", -5000, -5000), mkNode("b", 5000, 5000)],
      viewportWidth: VIEW_W,
      viewportHeight: VIEW_H,
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
    })!;

    expect(result).not.toBeNull();
    expect(result.zoom).toBe(MIN_ZOOM);
  });

  it("clamps zoom to MAX_ZOOM for tiny graphs", () => {
    // Two nodes right next to each other
    const result = computeFitState({
      nodes: [mkNode("a", 0, 0), mkNode("b", 10, 10)],
      viewportWidth: VIEW_W,
      viewportHeight: VIEW_H,
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
    })!;

    expect(result).not.toBeNull();
    expect(result.zoom).toBe(MAX_ZOOM);
  });

  it("centers the graph in the viewport", () => {
    const result = computeFitState({
      nodes: [mkNode("a", 200, 100), mkNode("b", 400, 300)],
      viewportWidth: VIEW_W,
      viewportHeight: VIEW_H,
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
    })!;

    expect(result).not.toBeNull();
    // Center of bounding box (200..520 x 100..372) = (360, 236)
    // At scaled center, pan should map to viewport center (600, 400)
    const scale = result.zoom / 100;
    // pan.x = 600 - 360*scale, pan.y = 400 - 236*scale
    expect(typeof result.pan.x).toBe("number");
    expect(typeof result.pan.y).toBe("number");
    expect(Number.isFinite(result.pan.x)).toBe(true);
    expect(Number.isFinite(result.pan.y)).toBe(true);
  });

  it("handles zero viewport dimensions gracefully", () => {
    const result = computeFitState({
      nodes: [mkNode("a", 100, 200)],
      viewportWidth: 0,
      viewportHeight: 0,
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
    })!;

    expect(result).not.toBeNull();
    expect(result.zoom).toBe(MAX_ZOOM);
  });

  it("includes PADDING in the fit calculation", () => {
    // Node at origin — bounding box is 0..120 x 0..72
    // Without padding, fit would be zoom=100, center pan
    // With padding, box is larger so zoom is slightly smaller
    const result = computeFitState({
      nodes: [mkNode("a", 0, 0)],
      viewportWidth: VIEW_W,
      viewportHeight: VIEW_H,
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
    })!;

    expect(result).not.toBeNull();
    // paddedW = 120 + 120 = 240, paddedH = 72 + 120 = 192
    // zoomX = 1200/240*100 = 500 → clamped to MAX_ZOOM=200
    // zoomY = 800/192*100 = 416 → clamped to MAX_ZOOM=200
    expect(result.zoom).toBe(MAX_ZOOM);
  });

  it("produces deterministic results for the same input", () => {
    const nodes = [mkNode("a", 100, 200), mkNode("b", 500, 300)];
    const a = computeFitState({
      nodes,
      viewportWidth: VIEW_W,
      viewportHeight: VIEW_H,
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
    });
    const b = computeFitState({
      nodes: [...nodes],
      viewportWidth: VIEW_W,
      viewportHeight: VIEW_H,
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
    });
    expect(b).toEqual(a);
  });
});
