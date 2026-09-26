import type { Node } from "../../contracts.generated/graph";
import type {
  TopologyHostScene,
  TopologyScene,
  TopologySegmentScene,
  TopologyServiceScene,
} from "./topology-scene";

/** A projected segment in scene order. */
export interface IndexedSegment {
  kind: "segment";
  id: string;
  node: TopologySegmentScene["node"];
  segment: TopologySegmentScene;
}

/** A projected host and the segment that places it. */
export interface IndexedHost {
  kind: "host";
  id: string;
  node: TopologyHostScene["node"];
  host: TopologyHostScene;
  segment: IndexedSegment;
}

/** A projected service and the host and segment that place it. */
export interface IndexedService {
  kind: "service";
  id: string;
  node: TopologyServiceScene["node"];
  service: TopologyServiceScene;
  host: IndexedHost;
  segment: IndexedSegment;
}

export type IndexedTopologyEntity =
  IndexedSegment | IndexedHost | IndexedService;

/**
 * Flat, ordered access to projected topology membership.
 *
 * `projectedEntityIds` deliberately excludes attachments and Unplaced floaters.
 * They are drawn outside the segment-host-service projection hierarchy.
 */
export interface TopologySceneIndex {
  segments: readonly IndexedSegment[];
  hosts: readonly IndexedHost[];
  services: readonly IndexedService[];
  /** Segment, host, and service entries in hierarchy traversal order. */
  projectedEntities: readonly IndexedTopologyEntity[];
  /** Nodes known to the scene, including attachments and Unplaced entries. */
  nodesById: ReadonlyMap<string, Node>;
  /** Projected segment, host, and service IDs only. */
  projectedEntityIds: ReadonlySet<string>;
}

/**
 * Indexes a scene without changing membership, ordering, or parent ownership.
 */
export function indexTopologyScene(scene: TopologyScene): TopologySceneIndex {
  const segments: IndexedSegment[] = [];
  const hosts: IndexedHost[] = [];
  const services: IndexedService[] = [];
  const projectedEntities: IndexedTopologyEntity[] = [];
  const nodesById = new Map<string, Node>();
  const projectedEntityIds = new Set<string>();

  for (const segment of scene.segments) {
    const indexedSegment: IndexedSegment = {
      kind: "segment",
      id: segment.id,
      node: segment.node,
      segment,
    };
    segments.push(indexedSegment);
    projectedEntities.push(indexedSegment);
    projectedEntityIds.add(segment.id);
    nodesById.set(segment.id, segment.node);

    for (const host of segment.hosts) {
      const indexedHost: IndexedHost = {
        kind: "host",
        id: host.id,
        node: host.node,
        host,
        segment: indexedSegment,
      };
      hosts.push(indexedHost);
      projectedEntities.push(indexedHost);
      projectedEntityIds.add(host.id);
      nodesById.set(host.id, host.node);

      for (const service of host.services) {
        const indexedService: IndexedService = {
          kind: "service",
          id: service.id,
          node: service.node,
          service,
          host: indexedHost,
          segment: indexedSegment,
        };
        services.push(indexedService);
        projectedEntities.push(indexedService);
        projectedEntityIds.add(service.id);
        nodesById.set(service.id, service.node);
      }
    }
  }

  for (const attachment of scene.attachments)
    nodesById.set(attachment.id, attachment.node);
  for (const entry of scene.unplaced) {
    if (entry.node && !nodesById.has(entry.entityId))
      nodesById.set(entry.entityId, entry.node);
  }

  return {
    segments,
    hosts,
    services,
    projectedEntities,
    nodesById,
    projectedEntityIds,
  };
}
