/**
 * Progressive detail for the unified topology canvas.
 *
 * The detail level selects representation only. World positions and segment
 * footprints never depend on it.
 */
export type TopologyDetailLevel = "far" | "medium" | "near";

export interface TopologyDetailThresholds {
  /** Zoom percent at which medium detail becomes eligible. */
  mediumZoom: number;
  /** Zoom percent at which near detail becomes eligible. */
  nearZoom: number;
  /**
   * Zoom band that a change must cross before the level follows. The band
   * stops a small wheel movement near a threshold from switching detail.
   */
  hysteresis: number;
}

export const DETAIL_THRESHOLDS: TopologyDetailThresholds = {
  mediumZoom: 65,
  nearZoom: 130,
  hysteresis: 12,
};

/** Detail for a new viewport. It applies no hysteresis. */
export function initialDetailLevel(
  zoom: number,
  thresholds: TopologyDetailThresholds = DETAIL_THRESHOLDS,
): TopologyDetailLevel {
  if (zoom >= thresholds.nearZoom) return "near";
  if (zoom >= thresholds.mediumZoom) return "medium";
  return "far";
}

/**
 * Next detail level for a zoom change.
 *
 * A level holds until the zoom crosses the next threshold by `hysteresis`.
 * Within that band the current level stays, regardless of the zoom direction.
 */
export function resolveDetailLevel(
  current: TopologyDetailLevel,
  zoom: number,
  thresholds: TopologyDetailThresholds = DETAIL_THRESHOLDS,
): TopologyDetailLevel {
  const nearEntry = thresholds.nearZoom + thresholds.hysteresis;
  const mediumEntry = thresholds.mediumZoom + thresholds.hysteresis;
  const mediumExit = thresholds.mediumZoom - thresholds.hysteresis;
  const nearExit = thresholds.nearZoom - thresholds.hysteresis;

  if (zoom >= nearEntry) return "near";
  if (current === "near") return zoom < nearExit ? "medium" : "near";
  if (zoom >= mediumEntry) return "medium";
  if (current === "medium") return zoom < mediumExit ? "far" : "medium";
  return "far";
}

/** Hosts appear once the canvas leaves far detail. */
export function showsHosts(level: TopologyDetailLevel): boolean {
  return level !== "far";
}

/** Service cards appear only at near detail. */
export function showsServices(level: TopologyDetailLevel): boolean {
  return level === "near";
}

/** Containment and ownership connectors appear only at near detail. */
export function showsStructuralEdges(level: TopologyDetailLevel): boolean {
  return level === "near";
}
