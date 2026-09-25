import { describe, expect, it } from "vitest";
import {
  DETAIL_THRESHOLDS,
  initialDetailLevel,
  resolveDetailLevel,
  showsHosts,
  showsServices,
  showsStructuralEdges,
} from "./semantic-zoom";

const mediumEntry = DETAIL_THRESHOLDS.mediumZoom + DETAIL_THRESHOLDS.hysteresis;
const mediumExit = DETAIL_THRESHOLDS.mediumZoom - DETAIL_THRESHOLDS.hysteresis;
const nearEntry = DETAIL_THRESHOLDS.nearZoom + DETAIL_THRESHOLDS.hysteresis;
const nearExit = DETAIL_THRESHOLDS.nearZoom - DETAIL_THRESHOLDS.hysteresis;

describe("semantic zoom", () => {
  it("maps a fresh viewport to a detail level", () => {
    expect(initialDetailLevel(DETAIL_THRESHOLDS.mediumZoom - 1)).toBe("far");
    expect(initialDetailLevel(DETAIL_THRESHOLDS.mediumZoom)).toBe("medium");
    expect(initialDetailLevel(DETAIL_THRESHOLDS.nearZoom)).toBe("near");
  });

  it("holds the current level inside a threshold band", () => {
    const belowMedium = DETAIL_THRESHOLDS.mediumZoom - 1;
    const aboveMedium = DETAIL_THRESHOLDS.mediumZoom + 1;

    expect(resolveDetailLevel("far", belowMedium)).toBe("far");
    expect(resolveDetailLevel("medium", belowMedium)).toBe("medium");
    expect(resolveDetailLevel("medium", aboveMedium)).toBe("medium");
    expect(resolveDetailLevel("near", DETAIL_THRESHOLDS.nearZoom - 1)).toBe(
      "near",
    );
  });

  it("switches level after the zoom crosses a threshold by the band", () => {
    expect(resolveDetailLevel("far", mediumEntry - 1)).toBe("far");
    expect(resolveDetailLevel("far", mediumEntry)).toBe("medium");
    expect(resolveDetailLevel("medium", mediumExit)).toBe("medium");
    expect(resolveDetailLevel("medium", mediumExit - 1)).toBe("far");
    expect(resolveDetailLevel("medium", nearEntry - 1)).toBe("medium");
    expect(resolveDetailLevel("medium", nearEntry)).toBe("near");
    expect(resolveDetailLevel("near", nearExit)).toBe("near");
    expect(resolveDetailLevel("near", nearExit - 1)).toBe("medium");
  });

  it("walks one level down at a time on a large jump", () => {
    expect(resolveDetailLevel("far", DETAIL_THRESHOLDS.nearZoom + 80)).toBe(
      "near",
    );
    expect(resolveDetailLevel("medium", DETAIL_THRESHOLDS.nearZoom + 80)).toBe(
      "near",
    );

    const lowZoom = DETAIL_THRESHOLDS.mediumZoom - 40;
    expect(resolveDetailLevel("near", lowZoom)).toBe("medium");
    expect(resolveDetailLevel("medium", lowZoom)).toBe("far");
  });

  it("keeps the level stable for a small oscillation near a threshold", () => {
    let level = resolveDetailLevel("medium", mediumEntry + 1);
    const settled = level;

    for (const zoom of [mediumEntry - 2, mediumEntry + 2, mediumEntry - 3]) {
      level = resolveDetailLevel(level, zoom);
    }

    expect(level).toBe(settled);
  });

  it("gates the representation of each level", () => {
    expect(showsHosts("far")).toBe(false);
    expect(showsHosts("medium")).toBe(true);
    expect(showsHosts("near")).toBe(true);

    expect(showsServices("medium")).toBe(false);
    expect(showsServices("near")).toBe(true);

    expect(showsStructuralEdges("medium")).toBe(false);
    expect(showsStructuralEdges("near")).toBe(true);
  });
});
