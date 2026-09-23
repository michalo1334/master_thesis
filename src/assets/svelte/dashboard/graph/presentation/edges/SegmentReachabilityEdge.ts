import type { Edge } from "../../../../contracts.generated/graph";

function policyLabel(edge: Edge): string {
  if (edge.type !== "SegmentReachability") return edge.type;
  const { protocol, port_start, port_end } = edge.data;
  if (port_start == null && port_end == null) return protocol;
  return `${protocol}:${port_start ?? "*"}-${port_end ?? "*"}`;
}

export const segmentReachabilityEdge = {
  color: "var(--ui-color-edge-segment-reachability)",
  dashArray: "5 3" as string | null,
  label: policyLabel,
};
