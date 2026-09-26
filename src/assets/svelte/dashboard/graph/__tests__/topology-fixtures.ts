import type {
  AuthenticatesToEdge,
  ContainsEdge,
  CredentialNode,
  Edge,
  GraphContract,
  HasVulnerabilityEdge,
  HostNode,
  MissionCapabilityNode,
  NetworkSegmentNode,
  Node,
  RunsEdge,
  SegmentReachabilityEdge,
  ServiceNode,
  StoresCredentialEdge,
  SupportsEdge,
  VulnerabilityNode,
} from "../../../contracts.generated/graph";
import type { TopologyProjection } from "../../../contracts.generated/dashboard/graph";
import type {
  Anchor,
  Attachment,
  FlowGroup,
  Host,
  Issue,
  PolicyGroup,
  Segment,
  Service,
} from "../../../contracts.generated/dashboard/graph/topology_projection";

export function graphContract(
  nodes: Node[],
  edges: Edge[] = [],
): GraphContract {
  return { id: "graph-1", title: "Graph", nodes, edges };
}

export function hostNode(id: string, x = 0, y = 0): HostNode {
  return {
    id,
    type: "Host",
    data: { name: id },
    view_data: { x_pos: x, y_pos: y },
  };
}

export function serviceNode(id: string, x = 0, y = 0): ServiceNode {
  return {
    id,
    type: "Service",
    data: { name: id, port: 8080, protocol: "tcp" },
    view_data: { x_pos: x, y_pos: y },
  };
}

export function segmentNode(id: string, x = 0, y = 0): NetworkSegmentNode {
  return {
    id,
    type: "NetworkSegment",
    data: { name: id, cidr: null },
    view_data: { x_pos: x, y_pos: y },
  };
}

export function vulnerabilityNode(id: string, x = 0, y = 0): VulnerabilityNode {
  return {
    id,
    type: "Vulnerability",
    data: {
      identifier: id,
      exploit_probability: 0.4,
      cvss: {
        attack_complexity: "low",
        attack_vector: "network",
        availability_impact: "none",
        confidentiality_impact: "low",
        integrity_impact: "low",
        privileges_required: "none",
        scope: "unchanged",
        user_interaction: "none",
      },
    },
    view_data: { x_pos: x, y_pos: y },
  };
}

export function credentialNode(id: string, x = 0, y = 0): CredentialNode {
  return {
    id,
    type: "Credential",
    data: { identifier: id, credential_type: "password" },
    view_data: { x_pos: x, y_pos: y },
  };
}

export function missionCapabilityNode(
  id: string,
  x = 0,
  y = 0,
): MissionCapabilityNode {
  return {
    id,
    type: "MissionCapability",
    data: {
      name: id,
      description: null,
      impact_weight: 1,
      min_operational_support: 1,
      required_flows: [],
    },
    view_data: { x_pos: x, y_pos: y },
  };
}

export function containsEdge(
  id: string,
  from: string,
  to: string,
): ContainsEdge {
  return { id, type: "Contains", from_id: from, to_id: to, data: {} };
}

export function runsEdge(id: string, from: string, to: string): RunsEdge {
  return { id, type: "Runs", from_id: from, to_id: to, data: {} };
}

export function reachabilityEdge(
  id: string,
  from: string,
  to: string,
): SegmentReachabilityEdge {
  return {
    id,
    type: "SegmentReachability",
    from_id: from,
    to_id: to,
    data: { protocol: "tcp" },
  };
}

export function hasVulnerabilityEdge(
  id: string,
  from: string,
  to: string,
): HasVulnerabilityEdge {
  return {
    id,
    type: "HasVulnerability",
    from_id: from,
    to_id: to,
    data: { granted_privilege: "user", required_privilege: "none" },
  };
}

export function storesCredentialEdge(
  id: string,
  from: string,
  to: string,
): StoresCredentialEdge {
  return {
    id,
    type: "StoresCredential",
    from_id: from,
    to_id: to,
    data: { required_privilege: "user" },
  };
}

export function authenticatesToEdge(
  id: string,
  from: string,
  to: string,
): AuthenticatesToEdge {
  return {
    id,
    type: "AuthenticatesTo",
    from_id: from,
    to_id: to,
    data: { granted_privilege: "user" },
  };
}

export function supportsEdge(
  id: string,
  from: string,
  to: string,
): SupportsEdge {
  return { id, type: "Supports", from_id: from, to_id: to, data: {} };
}

export function emptyProjection(): TopologyProjection {
  return {
    segments: [],
    hosts: [],
    services: [],
    attachments: [],
    policy_groups: [],
    flow_groups: [],
    issues: [],
  };
}

export function projectionOf(
  partial: Partial<TopologyProjection>,
): TopologyProjection {
  return { ...emptyProjection(), ...partial };
}

export function segmentRecord(
  id: string,
  hostIds: string[] = [],
  counts: { service_count?: number; context_count?: number } = {},
): Segment {
  return {
    id,
    host_ids: [...hostIds],
    host_count: hostIds.length,
    service_count: counts.service_count ?? 0,
    context_count: counts.context_count ?? 0,
  };
}

export function hostRecord(
  id: string,
  segmentId: string | null = null,
  serviceIds: string[] = [],
  contextCount = 0,
): Host {
  return {
    id,
    segment_id: segmentId,
    service_ids: [...serviceIds],
    service_count: serviceIds.length,
    context_count: contextCount,
  };
}

export function serviceRecord(
  id: string,
  hostId: string | null = null,
): Service {
  return { id, host_id: hostId };
}

export function anchorRecord(
  nodeId: string,
  edgeId: string,
  relationshipType: Anchor["relationship_type"],
): Anchor {
  return {
    node_id: nodeId,
    edge_id: edgeId,
    relationship_type: relationshipType,
  };
}

export function attachmentRecord(
  id: string,
  nodeType: Attachment["node_type"],
  anchors: Anchor[] = [],
): Attachment {
  return { id, node_type: nodeType, anchors };
}

export function policyGroupRecord(
  fromSegmentId: string,
  toSegmentId: string,
  edgeIds: string[] = [],
): PolicyGroup {
  return {
    from_segment_id: fromSegmentId,
    to_segment_id: toSegmentId,
    edge_ids: [...edgeIds],
  };
}

export function flowGroupRecord(
  sourceHostId: string,
  targetHostId: string,
  serviceIds: string[] = [],
  flowIds: string[] = [],
): FlowGroup {
  return {
    source_host_id: sourceHostId,
    target_host_id: targetHostId,
    service_ids: [...serviceIds],
    flow_ids: [...flowIds],
  };
}

export function issueRecord(
  code: Issue["code"],
  entityId: string,
  relatedIds: string[] = [],
): Issue {
  return {
    code,
    severity: "warning",
    entity_id: entityId,
    related_ids: [...relatedIds],
  };
}
