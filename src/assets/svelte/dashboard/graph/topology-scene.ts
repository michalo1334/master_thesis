import type {
  Edge,
  GraphContract,
  Node,
} from "../../contracts.generated/graph";
import type { TopologyProjection } from "../../contracts.generated/dashboard/graph";
import type {
  Anchor,
  Attachment,
  FlowGroup,
  Host,
  Issue,
  PolicyGroup,
  Segment,
  Service,
} from "../../contracts.generated/dashboard/graph/topology_projection";

export type TopologySegmentNode = Extract<Node, { type: "NetworkSegment" }>;
export type TopologyHostNode = Extract<Node, { type: "Host" }>;
export type TopologyServiceNode = Extract<Node, { type: "Service" }>;
export type TopologyContextNode = Extract<
  Node,
  { type: "Vulnerability" | "Credential" | "MissionCapability" }
>;
export type TopologyReachabilityEdge = Extract<
  Edge,
  { type: "SegmentReachability" }
>;

export interface TopologyServiceScene {
  id: string;
  node: TopologyServiceNode;
  service: Service;
  hostId: string | null;
}

export interface TopologyHostScene {
  id: string;
  node: TopologyHostNode;
  host: Host;
  segmentId: string | null;
  services: TopologyServiceScene[];
}

export interface TopologySegmentScene {
  id: string;
  node: TopologySegmentNode;
  segment: Segment;
  hosts: TopologyHostScene[];
}

export interface TopologyAttachmentAnchorScene {
  anchor: Anchor;
  node: Node;
  edge: Edge;
}

export interface TopologyAttachmentScene {
  id: string;
  node: TopologyContextNode;
  attachment: Attachment;
  /** Only anchors whose node and edge exist in the graph. */
  anchors: TopologyAttachmentAnchorScene[];
}

export interface TopologyPolicyGroupScene {
  group: PolicyGroup;
  from: TopologySegmentScene;
  to: TopologySegmentScene;
  /** Only policy edges that exist in the graph. */
  edges: TopologyReachabilityEdge[];
}

export interface TopologyFlowGroupScene {
  group: FlowGroup;
  source: TopologyHostScene;
  target: TopologyHostScene;
  /** Only flow services that exist in the graph. */
  services: TopologyServiceScene[];
  /**
   * Materialized flow identifiers. The projector derives them from segment
   * policy, so they have no matching edge in the wire graph.
   */
  flowIds: string[];
}

/**
 * How a projection reference fails to join.
 *
 * `attachment_type` and `segment_host` are contradictory projection records,
 * not absent graph entities. The adapter reports them and never repairs the
 * projection.
 */
export type TopologyMissingRelationship =
  | "segment_node"
  | "host_node"
  | "service_node"
  | "attachment_node"
  | "attachment_type"
  | "anchor_node"
  | "anchor_edge"
  | "policy_edge"
  | "policy_segment"
  | "flow_host"
  | "flow_service"
  | "segment_host";

export interface TopologyMissingReference {
  relationship: TopologyMissingRelationship;
  /**
   * Every projection record that carries or contradicts the reference, sorted.
   * Several records can reference the same absent entity, so one entry covers
   * all owners.
   */
  ownerIds: string[];
  referenceId: string;
}

/**
 * Why an entity appears in the Unplaced output.
 *
 * - `placement_issue`: the projector reported a typed placement issue.
 * - `no_placement`: the accepted projection gives the entity no usable owner,
 *   or its owner host has no segment placement.
 * - `missing_reference`: the projection references a graph entity that is
 *   absent, or two projection records contradict each other.
 * - `pending`: the entity changed after the accepted projection.
 */
export type TopologyUnplacedStatus =
  "placement_issue" | "no_placement" | "missing_reference" | "pending";

export interface TopologyUnplacedEntry {
  /** Stable key, unique inside the scene. */
  key: string;
  /** Entity id, or the missing reference id. */
  entityId: string;
  /** Graph node behind `entityId`, when the graph contains one. */
  node: Node | null;
  /** Graph edge behind `entityId`, when the graph contains one. */
  edge: Edge | null;
  status: TopologyUnplacedStatus;
  /** Projector issue that explains the placement. */
  issue: Issue | null;
  /** Projection reference that failed to join. */
  missing: TopologyMissingReference | null;
}

export interface TopologyScene {
  segments: TopologySegmentScene[];
  attachments: TopologyAttachmentScene[];
  policyGroups: TopologyPolicyGroupScene[];
  flowGroups: TopologyFlowGroupScene[];
  /** Every issue the projector reported, sorted by code and entity. */
  issues: Issue[];
  /** Issues, missing references, unplaced entities, and pending entities. */
  unplaced: TopologyUnplacedEntry[];
}

/** Graph entity that a control can select on the canvas. */
export interface TopologyEntitySelection {
  kind: "node" | "edge";
  id: string;
}

export interface TopologySceneOptions {
  /** Entities that changed after the accepted projection. */
  pendingEntityIds?: readonly string[];
}

/**
 * Graph entity an Unplaced entry can activate, or `null` when it has none.
 *
 * A broken projection reference can name an entity the graph does not contain.
 * Such an entry is reported with its reason but never selected, so the canvas
 * cannot hold a selection that points at nothing.
 */
export function unplacedSelection(
  entry: TopologyUnplacedEntry,
): TopologyEntitySelection | null {
  if (entry.node) return { kind: "node", id: entry.node.id };
  if (entry.edge) return { kind: "edge", id: entry.edge.id };
  return null;
}

/** Name of a graph entity, for visible text and accessible names. */
export function topologyEntityLabel(node: Node): string {
  switch (node.type) {
    case "Host":
    case "Service":
    case "NetworkSegment":
    case "MissionCapability":
      return node.data.name;
    case "Vulnerability":
    case "Credential":
      return node.data.identifier;
  }
}

/**
 * Joins a projection to graph entities by ID.
 *
 * Placement comes only from projection records: a segment record places the
 * hosts it lists, a host record owns the services it lists, and an attachment
 * record places its context node. A service renders through its owner host
 * inside a segment, so it is placed only when that host is placed too. The
 * adapter derives nothing from raw edges and never repairs contradictory
 * projection records. Entities without a usable placement, broken references,
 * projector issues, and entities pending a new projection appear in `unplaced`.
 *
 * Every array and nested ID list is sorted, so the same graph and projection
 * always produce the same scene.
 */
export function buildTopologyScene(
  graph: GraphContract,
  projection: TopologyProjection,
  options: TopologySceneOptions = {},
): TopologyScene {
  const nodes = new Map<string, Node>();
  for (const node of graph.nodes) nodes.set(node.id, node);
  const edges = new Map<string, Edge>();
  for (const edge of graph.edges) edges.set(edge.id, edge);

  const unplaced = new Map<string, TopologyUnplacedEntry>();
  const reportedEntityIds = new Set<string>();

  const addUnplaced = (entry: TopologyUnplacedEntry) => {
    if (unplaced.has(entry.key)) return;
    unplaced.set(entry.key, entry);
    reportedEntityIds.add(entry.entityId);
  };

  // One record per relationship and reference ID. Several projection records
  // can point at the same absent entity, and several segments can disagree with
  // the same host record. Both cases collapse into one Unplaced entry.
  const missing = new Map<
    string,
    {
      relationship: TopologyMissingRelationship;
      referenceId: string;
      ownerIds: Set<string>;
    }
  >();

  const addMissingReference = (
    relationship: TopologyMissingRelationship,
    ownerId: string,
    referenceId: string,
  ) => {
    const key = `${relationship}:${referenceId}`;
    const record = missing.get(key) ?? {
      relationship,
      referenceId,
      ownerIds: new Set<string>(),
    };
    record.ownerIds.add(ownerId);
    missing.set(key, record);
  };

  const services = new Map<string, TopologyServiceScene>();
  const hosts = new Map<string, TopologyHostScene>();
  const segments = new Map<string, TopologySegmentScene>();
  const attachments: TopologyAttachmentScene[] = [];

  for (const record of projection.hosts) {
    const node = nodes.get(record.id);
    if (!isHostNode(node)) {
      addMissingReference("host_node", record.id, record.id);
      continue;
    }

    hosts.set(record.id, {
      id: record.id,
      node,
      host: record,
      segmentId: record.segment_id ?? null,
      services: [],
    });
  }

  const ownedServiceIds = new Set<string>();

  for (const record of projection.services) {
    const node = nodes.get(record.id);
    if (!isServiceNode(node)) {
      addMissingReference("service_node", record.id, record.id);
      continue;
    }

    const scene: TopologyServiceScene = {
      id: record.id,
      node,
      service: record,
      hostId: record.host_id ?? null,
    };
    services.set(record.id, scene);

    const owner = scene.hostId ? hosts.get(scene.hostId) : undefined;
    if (scene.hostId && !owner) {
      addMissingReference("host_node", record.id, scene.hostId);
    } else if (owner) {
      owner.services.push(scene);
      ownedServiceIds.add(scene.id);
    }
  }

  for (const record of projection.segments) {
    const node = nodes.get(record.id);
    if (!isSegmentNode(node)) {
      addMissingReference("segment_node", record.id, record.id);
      continue;
    }

    const scene: TopologySegmentScene = {
      id: record.id,
      node,
      segment: record,
      hosts: [],
    };
    segments.set(record.id, scene);

    // `host_ids` is the only membership source. A host whose own record names a
    // different segment is a contradiction, not a membership to add here.
    for (const hostId of sortedUnique(record.host_ids)) {
      const host = hosts.get(hostId);
      if (!host) {
        addMissingReference("host_node", record.id, hostId);
        continue;
      }
      scene.hosts.push(host);
    }

    scene.hosts.sort(compareById);
  }

  const claimedHostIds = reportMembershipConflicts(
    hosts,
    segments,
    addMissingReference,
  );

  for (const host of hosts.values()) {
    if (host.segmentId && !segments.has(host.segmentId)) {
      addMissingReference("segment_node", host.id, host.segmentId);
    }
    host.services.sort(compareById);
  }

  for (const record of projection.attachments) {
    const node = nodes.get(record.id);
    if (!isContextNode(node)) {
      addMissingReference("attachment_node", record.id, record.id);
      continue;
    }
    // The projection owns the context kind. A graph node of another type is a
    // contradiction, so the attachment stays out of the scene.
    if (node.type !== record.node_type) {
      addMissingReference("attachment_type", record.id, record.id);
      continue;
    }

    const anchors: TopologyAttachmentAnchorScene[] = [];
    for (const anchor of record.anchors) {
      const anchorNode = nodes.get(anchor.node_id);
      const edge = edges.get(anchor.edge_id);
      if (!anchorNode) {
        addMissingReference("anchor_node", record.id, anchor.node_id);
      }
      if (!edge) {
        addMissingReference("anchor_edge", record.id, anchor.edge_id);
      }
      if (anchorNode && edge) anchors.push({ anchor, node: anchorNode, edge });
    }

    attachments.push({
      id: record.id,
      node,
      attachment: record,
      anchors: anchors.sort(compareAnchors),
    });
  }

  const policyGroups: TopologyPolicyGroupScene[] = [];
  for (const group of projection.policy_groups) {
    const ownerId = `${group.from_segment_id}:${group.to_segment_id}`;
    const from = segments.get(group.from_segment_id);
    const to = segments.get(group.to_segment_id);
    if (!from) {
      addMissingReference("policy_segment", ownerId, group.from_segment_id);
    }
    if (!to) {
      addMissingReference("policy_segment", ownerId, group.to_segment_id);
    }
    if (!from || !to) continue;

    const groupEdges: TopologyReachabilityEdge[] = [];
    for (const edgeId of group.edge_ids) {
      const edge = edges.get(edgeId);
      if (edge?.type === "SegmentReachability") {
        groupEdges.push(edge);
      } else {
        addMissingReference("policy_edge", ownerId, edgeId);
      }
    }

    policyGroups.push({ group, from, to, edges: groupEdges });
  }

  const flowGroups: TopologyFlowGroupScene[] = [];
  for (const group of projection.flow_groups) {
    const ownerId = `${group.source_host_id}:${group.target_host_id}`;
    const source = hosts.get(group.source_host_id);
    const target = hosts.get(group.target_host_id);
    if (!source) {
      addMissingReference("flow_host", ownerId, group.source_host_id);
    }
    if (!target) {
      addMissingReference("flow_host", ownerId, group.target_host_id);
    }
    if (!source || !target) continue;

    const groupServices: TopologyServiceScene[] = [];
    for (const serviceId of group.service_ids) {
      const service = services.get(serviceId);
      if (service) {
        groupServices.push(service);
      } else {
        addMissingReference("flow_service", ownerId, serviceId);
      }
    }

    flowGroups.push({
      group,
      source,
      target,
      services: groupServices,
      flowIds: [...group.flow_ids],
    });
  }

  const issues = [...projection.issues].sort(compareIssues);
  for (const issue of issues) {
    addUnplaced({
      key: `placement_issue:${issue.code}:${issue.entity_id}`,
      entityId: issue.entity_id,
      node: nodes.get(issue.entity_id) ?? null,
      edge: null,
      status: "placement_issue",
      issue,
      missing: null,
    });
  }

  for (const record of missing.values()) {
    addUnplaced({
      key: `missing_reference:${record.relationship}:${record.referenceId}`,
      entityId: record.referenceId,
      node: nodes.get(record.referenceId) ?? null,
      edge: edges.get(record.referenceId) ?? null,
      status: "missing_reference",
      issue: null,
      missing: {
        relationship: record.relationship,
        ownerIds: [...record.ownerIds].sort(),
        referenceId: record.referenceId,
      },
    });
  }

  for (const id of sortedUnique(options.pendingEntityIds ?? [])) {
    if (reportedEntityIds.has(id)) continue;
    const node = nodes.get(id) ?? null;
    const edge = node ? null : (edges.get(id) ?? null);
    if (!node && !edge) continue;
    addUnplaced({
      key: `pending:${id}`,
      entityId: id,
      node,
      edge,
      status: "pending",
      issue: null,
      missing: null,
    });
  }

  // A service renders through its owner host inside a segment. When no segment
  // claims that host, the service has no position either, so it joins the
  // Unplaced output. Ownership stays exactly as the projection states it.
  const unplacedServiceIds = new Set<string>();
  for (const service of services.values()) {
    if (!ownedServiceIds.has(service.id)) continue;
    if (reportedEntityIds.has(service.id)) continue;
    if (service.hostId !== null && claimedHostIds.has(service.hostId)) continue;
    unplacedServiceIds.add(service.id);
    addUnplaced({
      key: `no_placement:${service.id}`,
      entityId: service.id,
      node: service.node,
      edge: null,
      status: "no_placement",
      issue: null,
      missing: null,
    });
  }

  const placedNodeIds = new Set<string>([
    ...segments.keys(),
    ...claimedHostIds,
    ...[...ownedServiceIds].filter((id) => !unplacedServiceIds.has(id)),
    ...attachments
      .filter((attachment) => attachment.anchors.length > 0)
      .map((attachment) => attachment.id),
  ]);

  // Placement comes from ownership only: a segment record owns the hosts it
  // lists, a host record owns the services it lists, and an attachment record
  // owns its context node when at least one anchor resolves. Authored positions
  // stay geometry: they never become a segment or an owner here.
  for (const node of graph.nodes) {
    if (placedNodeIds.has(node.id) || reportedEntityIds.has(node.id)) continue;
    addUnplaced({
      key: `no_placement:${node.id}`,
      entityId: node.id,
      node,
      edge: null,
      status: "no_placement",
      issue: null,
      missing: null,
    });
  }

  return {
    segments: [...segments.values()].sort(compareById),
    attachments: attachments.sort(compareById),
    policyGroups: policyGroups.sort((a, b) =>
      compareKeys(
        [a.group.from_segment_id, a.group.to_segment_id],
        [b.group.from_segment_id, b.group.to_segment_id],
      ),
    ),
    flowGroups: flowGroups.sort((a, b) =>
      compareKeys(
        [a.group.source_host_id, a.group.target_host_id],
        [b.group.source_host_id, b.group.target_host_id],
      ),
    ),
    issues,
    unplaced: [...unplaced.values()].sort(
      (a, b) =>
        statusRank(a.status) - statusRank(b.status) ||
        compareKeys([a.key], [b.key]),
    ),
  };
}

/**
 * Reports contradictory segment membership and returns the host IDs that a
 * segment record actually lists.
 *
 * A host belongs to a segment when that segment lists it in `host_ids`. The
 * adapter reports every disagreement with `host.segment_id` and leaves the host
 * out of the segment. It never adds a host that `host_ids` omits.
 */
function reportMembershipConflicts(
  hosts: Map<string, TopologyHostScene>,
  segments: Map<string, TopologySegmentScene>,
  addMissingReference: (
    relationship: TopologyMissingRelationship,
    ownerId: string,
    referenceId: string,
  ) => void,
): Set<string> {
  const claimants = new Map<string, Set<string>>();
  for (const segment of segments.values()) {
    for (const host of segment.hosts) {
      const owners = claimants.get(host.id) ?? new Set<string>();
      owners.add(segment.id);
      claimants.set(host.id, owners);
    }
  }

  for (const host of hosts.values()) {
    const claiming = claimants.get(host.id) ?? new Set<string>();
    const named = host.segmentId;
    const namedSegment = named === null ? undefined : segments.get(named);

    if (namedSegment && !claiming.has(namedSegment.id)) {
      addMissingReference("segment_host", namedSegment.id, host.id);
    }
    for (const segmentId of claiming) {
      if (namedSegment?.id === segmentId) continue;
      addMissingReference("segment_host", segmentId, host.id);
    }
  }

  return new Set(claimants.keys());
}

/**
 * Placement issues first, then entities the projection cannot place, then
 * broken references, then entities with a pending projection request.
 */
function statusRank(status: TopologyUnplacedStatus): number {
  switch (status) {
    case "placement_issue":
      return 0;
    case "no_placement":
      return 1;
    case "missing_reference":
      return 2;
    case "pending":
      return 3;
  }
}

function sortedUnique(ids: readonly string[]): string[] {
  return [...new Set(ids)].sort();
}

function isSegmentNode(node: Node | undefined): node is TopologySegmentNode {
  return node?.type === "NetworkSegment";
}

function isHostNode(node: Node | undefined): node is TopologyHostNode {
  return node?.type === "Host";
}

function isServiceNode(node: Node | undefined): node is TopologyServiceNode {
  return node?.type === "Service";
}

function isContextNode(node: Node | undefined): node is TopologyContextNode {
  return (
    node?.type === "Vulnerability" ||
    node?.type === "Credential" ||
    node?.type === "MissionCapability"
  );
}

function compareById<T extends { id: string }>(a: T, b: T): number {
  return compareKeys([a.id], [b.id]);
}

function compareAnchors(
  a: TopologyAttachmentAnchorScene,
  b: TopologyAttachmentAnchorScene,
): number {
  return compareKeys(
    [a.anchor.node_id, a.anchor.edge_id],
    [b.anchor.node_id, b.anchor.edge_id],
  );
}

function compareIssues(a: Issue, b: Issue): number {
  return compareKeys(
    [a.code, a.entity_id, ...a.related_ids],
    [b.code, b.entity_id, ...b.related_ids],
  );
}

function compareKeys(a: readonly string[], b: readonly string[]): number {
  const length = Math.min(a.length, b.length);
  for (let index = 0; index < length; index++) {
    const left = a[index]!;
    const right = b[index]!;
    if (left < right) return -1;
    if (left > right) return 1;
  }
  return a.length - b.length;
}
