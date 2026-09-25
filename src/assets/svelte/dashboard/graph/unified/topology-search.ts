import type { Node } from "../../../contracts.generated/graph";
import { topologyEntityLabel, type TopologyScene } from "../topology-scene";

export interface TopologySearchResult {
  /** Graph entity ID. */
  id: string;
  node: Node;
  /** Visible label of the entity. */
  label: string;
  /** Placement path, for orientation in the result list. */
  path: string;
  /** True when the projection cannot place the entity. */
  unplaced: boolean;
}

export const DEFAULT_SEARCH_LIMIT = 8;

/** Path shown for an entity that leaves the segment hierarchy. */
export const ATTACHED_CONTEXT_PATH = "Attached context";
/** Path shown for an entity the projection cannot place. */
export const UNPLACED_PATH = "Unplaced";

interface RankedResult {
  result: TopologySearchResult;
  rank: number;
  order: number;
}

/**
 * Finds entities whose label or type matches the query.
 *
 * Search reads the scene and reports matches. It never filters the graph,
 * changes placement, or moves geometry. Results are deterministic: a label
 * prefix ranks above a label substring, which ranks above a type match, and
 * equal ranks keep scene order.
 */
export function searchTopology(
  scene: TopologyScene,
  query: string,
  limit: number = DEFAULT_SEARCH_LIMIT,
): TopologySearchResult[] {
  const needle = query.trim().toLowerCase();
  if (!needle || limit <= 0) return [];

  const seen = new Set<string>();
  const matches: RankedResult[] = [];
  let order = 0;

  const add = (node: Node, path: string, unplaced: boolean): void => {
    if (seen.has(node.id)) return;
    seen.add(node.id);

    const label = topologyEntityLabel(node);
    const lowerLabel = label.toLowerCase();
    const rank = lowerLabel.startsWith(needle)
      ? 0
      : lowerLabel.includes(needle)
        ? 1
        : node.type.toLowerCase().includes(needle)
          ? 2
          : -1;
    if (rank < 0) return;

    matches.push({
      result: { id: node.id, node, label, path, unplaced },
      rank,
      order: order++,
    });
  };

  for (const segment of scene.segments) {
    add(segment.node, segment.node.data.name, false);
    for (const host of segment.hosts) {
      add(
        host.node,
        `${segment.node.data.name} / ${host.node.data.name}`,
        false,
      );
      for (const service of host.services) {
        add(
          service.node,
          `${segment.node.data.name} / ${host.node.data.name} / ${service.node.data.name}`,
          false,
        );
      }
    }
  }

  for (const attachment of scene.attachments) {
    add(attachment.node, ATTACHED_CONTEXT_PATH, false);
  }

  for (const entry of scene.unplaced) {
    if (entry.node) add(entry.node, UNPLACED_PATH, true);
  }

  matches.sort((a, b) => a.rank - b.rank || a.order - b.order);
  return matches.slice(0, limit).map((entry) => entry.result);
}
