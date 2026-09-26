import type { GraphContract } from "../../contracts.generated/graph";
import type {
  TopologyAttachmentScene,
  TopologyFlowGroupScene,
  TopologyPolicyGroupScene,
  TopologyScene,
} from "./topology-scene";
import { indexTopologyScene } from "./topology-scene-index";

/**
 * Entities and grouped relationships the canvas keeps at full emphasis.
 *
 * The lens derives every member from projection records. It never adds a graph
 * entity that the accepted projection does not place.
 */
export interface TopologyLens {
  /** True when at least one focus entity resolves inside the scene. */
  active: boolean;
  /** Focus entities that resolve inside the scene, in input order. */
  focusIds: readonly string[];
  /** Focus entities plus their structural neighbors and attached context. */
  visibleIds: ReadonlySet<string>;
  /** `Contains` and `Runs` edges between two visible entities. */
  structuralEdgeIds: ReadonlySet<string>;
  /** Grouped policy relationships that touch a visible segment. */
  policyKeys: ReadonlySet<string>;
  /** Grouped flow relationships that touch a visible host. */
  flowKeys: ReadonlySet<string>;
}

/** Stable key of a grouped policy relationship. */
export function policyGroupKey(group: TopologyPolicyGroupScene): string {
  return `${group.group.from_segment_id}:${group.group.to_segment_id}`;
}

/**
 * Stable key of a grouped flow relationship.
 *
 * Several service sets can share one host pair, so the key repeats the service
 * ids that the canvas already renders in the relationship label.
 */
export function flowGroupKey(group: TopologyFlowGroupScene): string {
  return `${group.group.source_host_id}:${group.group.target_host_id}:${group.group.service_ids.join(",")}`;
}

/**
 * Reveals the neighborhood of the focus entities.
 *
 * Disclosure resolves through projection membership only: a focused segment
 * reveals its hosts, a focused host reveals its segment and services, and
 * attached context reveals its anchors. Grouped policy and flow relationships
 * stay visible while they touch a revealed segment or host.
 */
export function computeTopologyLens(
  graph: GraphContract,
  scene: TopologyScene,
  focusIds: readonly string[],
): TopologyLens {
  const index = indexTopologyScene(scene);
  const segments = new Map(
    index.segments.map((entry) => [entry.id, entry.segment]),
  );
  const hosts = new Map(index.hosts.map((entry) => [entry.id, entry.host]));
  const services = new Map(
    index.services.map((entry) => [
      entry.id,
      { service: entry.service, hostId: entry.host.id },
    ]),
  );
  const attachments = new Map<string, TopologyAttachmentScene>(
    scene.attachments.map((entry) => [entry.id, entry]),
  );

  const resolvedFocusIds: string[] = [];
  for (const id of focusIds) {
    if (resolvedFocusIds.includes(id)) continue;
    if (
      segments.has(id) ||
      hosts.has(id) ||
      services.has(id) ||
      attachments.has(id)
    )
      resolvedFocusIds.push(id);
  }

  const visible = new Set<string>();
  const structuralEdgeIds = new Set<string>();
  const policyKeys = new Set<string>();
  const flowKeys = new Set<string>();

  function addSegment(segmentId: string): void {
    if (visible.has(segmentId)) return;
    visible.add(segmentId);
    for (const group of scene.policyGroups) {
      if (
        group.group.from_segment_id !== segmentId &&
        group.group.to_segment_id !== segmentId
      )
        continue;
      policyKeys.add(policyGroupKey(group));
    }
    const segment = segments.get(segmentId);
    if (!segment) return;
    for (const host of segment.hosts) addHost(host.id);
  }

  function addHost(hostId: string): void {
    if (visible.has(hostId)) return;
    visible.add(hostId);
    const host = hosts.get(hostId);
    if (!host) return;
    for (const service of host.services) visible.add(service.id);
    addAttachmentsOf(hostId);
    for (const group of scene.flowGroups) {
      if (
        group.group.source_host_id !== hostId &&
        group.group.target_host_id !== hostId
      )
        continue;
      flowKeys.add(flowGroupKey(group));
    }
    if (host.segmentId) addSegment(host.segmentId);
  }

  function addService(serviceId: string): void {
    const entry = services.get(serviceId);
    if (!entry) return;
    visible.add(serviceId);
    addHost(entry.hostId);
  }

  function addAttachmentsOf(hostId: string): void {
    for (const attachment of scene.attachments) {
      if (!attachment.anchors.some((anchor) => anchor.node.id === hostId))
        continue;
      addAttachment(attachment);
    }
  }

  function addAttachment(attachment: TopologyAttachmentScene): void {
    if (visible.has(attachment.id)) return;
    visible.add(attachment.id);
    for (const anchor of attachment.anchors) addEntity(anchor.node.id);
  }

  function addEntity(id: string): void {
    if (visible.has(id)) return;
    if (segments.has(id)) return addSegment(id);
    if (hosts.has(id)) return addHost(id);
    if (services.has(id)) return addService(id);
    const attachment = attachments.get(id);
    if (attachment) addAttachment(attachment);
  }

  for (const id of resolvedFocusIds) addEntity(id);

  for (const edge of graph.edges) {
    if (edge.type !== "Contains" && edge.type !== "Runs") continue;
    if (visible.has(edge.from_id) && visible.has(edge.to_id))
      structuralEdgeIds.add(edge.id);
  }

  return {
    active: resolvedFocusIds.length > 0,
    focusIds: resolvedFocusIds,
    visibleIds: visible,
    structuralEdgeIds,
    policyKeys,
    flowKeys,
  };
}
