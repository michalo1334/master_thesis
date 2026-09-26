import type { Node } from "../../../contracts.generated/graph";

/**
 * Node types a canvas control can create.
 *
 * The order drives the Add menu, so it stays stable.
 */
export const TOPOLOGY_NODE_TYPES = [
  "Host",
  "Service",
  "Vulnerability",
  "Credential",
  "NetworkSegment",
  "MissionCapability",
] as const satisfies readonly Node["type"][];
