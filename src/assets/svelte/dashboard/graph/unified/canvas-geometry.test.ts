import { describe, expect, it } from "vitest";
import {
  boundsOfRects,
  connectRects,
  fitRects,
  inflateRect,
  pointInRect,
  pointInRectInterior,
  rectCenter,
  rectanglesOverlap,
  type Rect,
} from "./canvas-geometry";
import { MAX_ZOOM } from "../canvas/canvasState";

function rect(x: number, y: number, width: number, height: number): Rect {
  return { x, y, width, height };
}

describe("canvas geometry", () => {
  it("returns the rectangle center", () => {
    expect(rectCenter(rect(10, 20, 40, 60))).toEqual({ x: 30, y: 50 });
  });

  it("connects two rectangles at their facing borders", () => {
    expect(connectRects(rect(0, 0, 100, 100), rect(300, 0, 100, 100))).toEqual({
      source: { x: 100, y: 50 },
      target: { x: 300, y: 50 },
    });
  });

  it("handles rectangles of different sizes", () => {
    expect(connectRects(rect(0, 0, 400, 100), rect(600, 0, 100, 100))).toEqual({
      source: { x: 400, y: 50 },
      target: { x: 600, y: 50 },
    });
  });

  it("clips diagonally at a shared corner", () => {
    const path = connectRects(rect(0, 0, 100, 100), rect(100, 100, 100, 100));

    expect(path.source.x).toBeCloseTo(100);
    expect(path.source.y).toBeCloseTo(100);
    expect(path.target.x).toBeCloseTo(100);
    expect(path.target.y).toBeCloseTo(100);
  });

  it("clips a line from a container to a member inside it", () => {
    const path = connectRects(rect(0, 0, 400, 300), rect(100, 100, 120, 72));

    expect(path.source.x).toBeCloseTo(0);
    expect(path.source.y).toBeCloseTo(80);
    expect(path.target.x).toBeCloseTo(220);
    expect(path.target.y).toBeCloseTo(157);
  });

  it("returns the same point for identical rectangles", () => {
    const square = rect(5, 5, 50, 50);
    expect(connectRects(square, square)).toEqual({
      source: { x: 30, y: 30 },
      target: { x: 30, y: 30 },
    });
  });

  it("measures the bounds of several rectangles", () => {
    expect(
      boundsOfRects([rect(10, 10, 100, 50), rect(200, 80, 40, 20)]),
    ).toEqual(rect(10, 10, 230, 90));
    expect(boundsOfRects([])).toBeNull();
  });

  it("fits rectangles into a viewport", () => {
    const result = fitRects([rect(0, 0, 200, 100)], {
      width: 800,
      height: 600,
    });

    expect(result).toEqual({ zoom: MAX_ZOOM, pan: { x: 200, y: 200 } });
  });

  it("respects the viewport that constrains the fit", () => {
    const result = fitRects([rect(0, 0, 1000, 200)], {
      width: 500,
      height: 800,
    });

    expect(result!.zoom).toBeCloseTo((500 / 1120) * 100, 5);
  });

  it("returns null when there is nothing to fit", () => {
    expect(fitRects([], { width: 800, height: 600 })).toBeNull();
  });

  it("includes rectangle boundaries for pointer hit-testing", () => {
    const area = rect(10, 10, 100, 50);
    expect(pointInRect({ x: 10, y: 10 }, area)).toBe(true);
    expect(pointInRect({ x: 110, y: 60 }, area)).toBe(true);
    expect(pointInRect({ x: 9, y: 30 }, area)).toBe(false);
    expect(pointInRect({ x: 50, y: 61 }, area)).toBe(false);
  });

  it("keeps rectangle boundaries outside strict layout containment", () => {
    const area = rect(10, 10, 100, 50);
    expect(pointInRectInterior({ x: 10, y: 30 }, area)).toBe(false);
    expect(pointInRectInterior({ x: 50, y: 60 }, area)).toBe(false);
    expect(pointInRectInterior({ x: 50, y: 30 }, area)).toBe(true);
  });

  it("inflates rectangles and detects overlap with a layout gap", () => {
    const area = rect(10, 20, 100, 50);
    expect(inflateRect(area, 8)).toEqual(rect(2, 12, 116, 66));
    expect(rectanglesOverlap(area, rect(110, 20, 40, 50))).toBe(false);
    expect(rectanglesOverlap(area, rect(110, 20, 40, 50), 1)).toBe(true);
  });
});
