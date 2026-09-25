import type {
  Edge,
  GraphContract,
  Node,
} from "../../../contracts.generated/graph";
import type { TopologyProjection } from "../../../contracts.generated/dashboard/graph";
import {
  buildTopologyScene,
  topologyEntityLabel,
  type TopologyHostScene,
} from "../../graph/topology-scene";
import { flowGroupKey, policyGroupKey } from "../../graph/topology-lens";
import {
  topologyPlacement,
  type TopologyPlacement,
} from "../../graph/topology-placement";

export type SelectionProjectionSource = "revision" | "draft";

export interface SelectionTopology {
  /** Placement status and typed reason, or `null` when the projection places it. */
  placement: TopologyPlacement | null;
  /** Visible relationship summary for the selected entity, ordered. */
  relationships: readonly string[];
  /** True when visible operational flows come from unsaved edits. */
  draftReachability: boolean;
}

export interface SelectionTopologyOptions {
  projection?: TopologyProjection;
  pendingEntityIds?: readonly string[];
  projectionSource?: SelectionProjectionSource;
}

/**
 * Contextual inspector data for one selected entity.
 *
 * Every relationship comes from the accepted projection: membership, anchors,
 * and grouped policy or flow records. Raw edges supply no meaning, and an edge
 * selection carries no topology relationship of its own.
 */
export function selectionTopology(
  graph: GraphContract,
  selectable: Node | Edge,
  options: SelectionTopologyOptions = {},
): SelectionTopology {
  const projection = options.projection;
  if (!projection || !("view_data" in selectable)) {
    return { placement: null, relationships: [], draftReachability: false };
  }

  const scene = buildTopologyScene(graph, projection, {
    pendingEntityIds: options.pendingEntityIds ?? [],
  });
  const nodeById = new Map<string, Node>(
    graph.nodes.map((node) => [node.id, node]),
  );
  const hosts = new Map<string, TopologyHostScene>();
  for (const segment of scene.segments)
    for (const host of segment.hosts) hosts.set(host.id, host);

  const label = (id: string): string => {
    const node = nodeById.get(id);
    return node ? topologyEntityLabel(node) : id;
  };
  const relationships = new Set<string>();
  const policyKeys = new Set<string>();
  const flowKeys = new Set<string>();
  const flowHostIds = new Set<string>();

  const add = (label: string): void => {
    relationships.add(label);
  };

  const addPolicies = (segmentId: string): void => {
    for (const group of scene.policyGroups) {
      const from = group.group.from_segment_id;
      const to = group.group.to_segment_id;
      if (from !== segmentId && to !== segmentId) continue;
      policyKeys.add(policyGroupKey(group));
      add(
        from === to
          ? `Self-segment policy · ${countLabel(group.edges.length)}`
          : `Segment policy to ${label(from === segmentId ? to : from)} · ${countLabel(group.edges.length)}`,
      );
    }
  };

  /**
   * Context anchored to a host.
   *
   * The row names the attached context entity, not the anchor host, so two
   * distinct attachments to the same host stay distinct rows.
   */
  const addContextOf = (hostId: string): void => {
    for (const attachment of scene.attachments) {
      for (const anchor of attachment.anchors) {
        if (anchor.node.id !== hostId) continue;
        add(
          `${anchor.anchor.relationship_type} · ${topologyEntityLabel(attachment.node)}`,
        );
      }
    }
  };

  const addSegment = (segmentId: string): void => {
    addPolicies(segmentId);
    const segment = scene.segments.find((entry) => entry.id === segmentId);
    for (const host of segment?.hosts ?? []) {
      flowHostIds.add(host.id);
      add(`Contains ${topologyEntityLabel(host.node)}`);
      addContextOf(host.id);
    }
  };

  switch (selectable.type) {
    case "NetworkSegment": {
      addSegment(selectable.id);
      break;
    }
    case "Host": {
      const host = hosts.get(selectable.id);
      flowHostIds.add(selectable.id);
      if (host?.segmentId) {
        add(`Member of ${label(host.segmentId)}`);
        addPolicies(host.segmentId);
      }
      for (const service of host?.services ?? [])
        add(`Runs ${topologyEntityLabel(service.node)}`);
      addContextOf(selectable.id);
      break;
    }
    case "Service": {
      const host = [...hosts.values()].find((entry) =>
        entry.services.some((service) => service.id === selectable.id),
      );
      if (!host) break;
      flowHostIds.add(host.id);
      add(`Runs on ${topologyEntityLabel(host.node)}`);
      if (host.segmentId) add(`Member of ${label(host.segmentId)}`);
      break;
    }
    default: {
      for (const attachment of scene.attachments) {
        if (attachment.id !== selectable.id) continue;
        for (const anchor of attachment.anchors) {
          flowHostIds.add(anchor.node.id);
          add(
            `${anchor.anchor.relationship_type} · ${topologyEntityLabel(anchor.node)}`,
          );
        }
      }
    }
  }

  for (const group of scene.flowGroups) {
    const key = flowGroupKey(group);
    const touchesHost =
      flowHostIds.has(group.group.source_host_id) ||
      flowHostIds.has(group.group.target_host_id);
    const touchesService = group.services.some(
      (service) => service.id === selectable.id,
    );
    if (!touchesHost && !touchesService) continue;
    flowKeys.add(key);
    add(
      `Operational flow ${label(group.group.source_host_id)} → ${label(
        group.group.target_host_id,
      )} · ${countLabel(group.flowIds.length)}`,
    );
  }

  return {
    placement: topologyPlacement(scene, selectable.id),
    relationships: [...relationships],
    draftReachability:
      options.projectionSource === "draft" && flowKeys.size > 0,
  };
}

function countLabel(count: number): string {
  return `${count} ${count === 1 ? "relationship" : "relationships"}`;
}
