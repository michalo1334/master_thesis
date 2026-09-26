import type { Issue } from "../../contracts.generated/dashboard/graph/topology_projection";
import type {
  TopologyMissingRelationship,
  TopologyScene,
  TopologyUnplacedEntry,
} from "./topology-scene";

/** Typed reason for each projector placement issue. */
export const ISSUE_REASONS: Record<Issue["code"], string> = {
  host_without_segment: "no segment",
  host_multiple_segments: "multiple segments",
  service_without_host: "no host",
  service_multiple_hosts: "multiple hosts",
  context_without_anchor: "no anchor",
};

/** Typed reason for each projection reference that fails to join. */
export const MISSING_REASONS: Record<TopologyMissingRelationship, string> = {
  segment_node: "missing segment",
  host_node: "missing host",
  service_node: "missing service",
  attachment_node: "missing context node",
  attachment_type: "context type mismatch",
  anchor_node: "missing anchor entity",
  anchor_edge: "missing anchor relationship",
  policy_edge: "missing policy relationship",
  policy_segment: "missing policy segment",
  flow_host: "missing flow host",
  flow_service: "missing flow service",
  segment_host: "segment membership mismatch",
};

export interface TopologyPlacement {
  status: TopologyUnplacedEntry["status"];
  /** Machine-readable reason: a projector issue code or a failed reference. */
  reasonCode: string;
  /** Human-readable reason for the canvas and the inspector. */
  reason: string;
}

/**
 * Typed reason that an entity has no topology placement.
 *
 * The reason comes from the projection: a projector issue code, a failed
 * projection reference, or the entity kind when the projection places nothing.
 * The caller never guesses a reason from raw edges.
 */
export function unplacedReason(entry: TopologyUnplacedEntry): string {
  if (entry.issue) return ISSUE_REASONS[entry.issue.code] ?? entry.issue.code;
  if (entry.missing)
    return MISSING_REASONS[entry.missing.relationship] ?? "missing reference";
  if (entry.status === "pending") return "awaiting topology update";
  switch (entry.node?.type) {
    case undefined:
      return "missing reference";
    case "Host":
      return "no segment";
    case "Service":
      return "no host";
    case "Vulnerability":
    case "Credential":
    case "MissionCapability":
      return "no anchor";
    default:
      return "no topology placement";
  }
}

/** Machine-readable form of `unplacedReason`, for the Unplaced tray. */
export function unplacedReasonCode(entry: TopologyUnplacedEntry): string {
  if (entry.issue) return entry.issue.code;
  if (entry.missing) return entry.missing.relationship;
  return entry.status;
}

/**
 * Placement status of one entity, or `null` when the projection places it.
 *
 * The scene sorts its Unplaced output, so the first entry for an entity is
 * stable for the same graph and projection.
 */
export function topologyPlacement(
  scene: TopologyScene,
  entityId: string,
): TopologyPlacement | null {
  const entry = scene.unplaced.find((item) => item.entityId === entityId);
  if (!entry) return null;
  return {
    status: entry.status,
    reasonCode: unplacedReasonCode(entry),
    reason: unplacedReason(entry),
  };
}
