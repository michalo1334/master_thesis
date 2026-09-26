import { describe, expect, it } from "vitest";
import {
  DRAG_THRESHOLD,
  exceedsDragThreshold,
  pointerDelta,
  screenDeltaToWorld,
  translatePositionMap,
} from "./pointer-math";

describe("pointer math", () => {
  it("calculates a pointer delta and applies the shared drag threshold", () => {
    expect(pointerDelta({ x: 12, y: -4 }, { x: 15, y: 0 })).toEqual({
      x: 3,
      y: 4,
    });
    expect(exceedsDragThreshold({ x: 2, y: 3 })).toBe(false);
    expect(exceedsDragThreshold({ x: 0, y: DRAG_THRESHOLD })).toBe(true);
  });

  it("converts screen deltas to world deltas at the active zoom", () => {
    expect(screenDeltaToWorld({ x: 20, y: -10 }, 50)).toEqual({
      x: 40,
      y: -20,
    });
    expect(screenDeltaToWorld({ x: 20, y: -10 }, 200)).toEqual({
      x: 10,
      y: -5,
    });
  });

  it("translates only ids with recorded origin positions", () => {
    const origins = new Map([
      ["first", { x: 10, y: 20 }],
      ["second", { x: -5, y: 3 }],
    ]);

    expect([
      ...translatePositionMap(["second", "missing", "first"], origins, {
        x: 4,
        y: -2,
      }),
    ]).toEqual([
      ["second", { x: -1, y: 1 }],
      ["first", { x: 14, y: 18 }],
    ]);
  });
});
