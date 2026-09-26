import type { Node } from "../../../contracts.generated/graph";
import {
  type IndexedTopologyEntity,
  indexTopologyScene,
} from "../topology-scene-index";
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

/** Returns the search precedence for a node, or `-1` when it does not match. */
export function topologySearchMatchRank(node: Node, query: string): number {
  const needle = query.trim().toLowerCase();
  if (!needle) return -1;

  const label = topologyEntityLabel(node).toLowerCase();
  return [
    label.startsWith(needle),
    label.includes(needle),
    node.type.toLowerCase().includes(needle),
  ].findIndex(Boolean);
}

function projectedPath(entity: IndexedTopologyEntity): string {
  switch (entity.kind) {
    case "segment":
      return entity.segment.node.data.name;
    case "host":
      return `${entity.segment.node.data.name} / ${entity.host.node.data.name}`;
    case "service":
      return `${entity.segment.node.data.name} / ${entity.host.host.node.data.name} / ${entity.service.node.data.name}`;
  }
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

  const index = indexTopologyScene(scene);
  const seen = new Set<string>();
  const matches: RankedResult[] = [];
  let order = 0;

  const add = (node: Node, path: string, unplaced: boolean): void => {
    if (seen.has(node.id)) return;
    seen.add(node.id);

    const label = topologyEntityLabel(node);
    const rank = topologySearchMatchRank(node, needle);
    if (rank < 0) return;

    matches.push({
      result: { id: node.id, node, label, path, unplaced },
      rank,
      order: order++,
    });
  };

  for (const entity of index.projectedEntities)
    add(entity.node, projectedPath(entity), false);

  for (const attachment of scene.attachments) {
    add(attachment.node, ATTACHED_CONTEXT_PATH, false);
  }

  for (const entry of scene.unplaced) {
    if (entry.node) add(entry.node, UNPLACED_PATH, true);
  }

  matches.sort((a, b) => a.rank - b.rank || a.order - b.order);
  return matches.slice(0, limit).map((entry) => entry.result);
}
