import type {
  Edge,
  GraphProjectionOperationalFlow,
  LoadedGraph,
  NetworkSegmentNode,
  Node,
} from "../../contract";
import { resolveOwnership } from "../ownership";

export interface NetworkHost {
  id: string;
  node: Extract<Node, { type: "Host" }>;
  segmentId: string;
  services: Array<{
    node: Extract<Node, { type: "Service" }>;
    vulnerabilities: Extract<Node, { type: "Vulnerability" }>[];
  }>;
}

export interface NetworkSegment {
  id: string;
  name: string;
  cidr?: string | null;
  node?: NetworkSegmentNode;
  hosts: NetworkHost[];
  position: { x: number; y: number };
}

export interface NetworkSegmentLink {
  id: string;
  sourceId: string;
  targetId: string;
  edgeIds: string[];
}

export interface NetworkOperationalFlow {
  id: string;
  sourceId: string;
  sourceName: string;
  sourcePosition: { x: number; y: number };
  targetId: string;
  targetPosition: { x: number; y: number };
  serviceId: string;
  serviceName: string;
}

export interface NetworkProjection {
  hosts: NetworkHost[];
  segments: NetworkSegment[];
  segmentLinks: NetworkSegmentLink[];
  operationalFlows: NetworkOperationalFlow[];
}

export function projectNetwork(
  graph: LoadedGraph,
  serverFlows?: readonly GraphProjectionOperationalFlow[],
): NetworkProjection {
  const nodesById = new Map(graph.nodes.map((node) => [node.id, node]));
  const servicesByHostId = new Map<
    string,
    Extract<Node, { type: "Service" }>[]
  >();
  const vulnerabilitiesByServiceId = new Map<
    string,
    Extract<Node, { type: "Vulnerability" }>[]
  >();
  const ownership = resolveOwnership(graph.nodes, graph.edges);

  for (const node of graph.nodes) {
    if (node.type === "Service") {
      const hostId = ownership.get(node.id);
      if (hostId)
        (
          servicesByHostId.get(hostId) ??
          servicesByHostId.set(hostId, []).get(hostId)!
        ).push(node);
    }
    if (node.type === "Vulnerability") {
      const serviceId = ownership.get(node.id);
      if (serviceId)
        (
          vulnerabilitiesByServiceId.get(serviceId) ??
          vulnerabilitiesByServiceId.set(serviceId, []).get(serviceId)!
        ).push(node);
    }
  }

  const segmentsById = new Map(
    graph.nodes
      .filter(
        (node): node is NetworkSegmentNode => node.type === "NetworkSegment",
      )
      .map((node) => [node.id, node]),
  );
  const segmentIdByHostId = new Map<string, string>();
  for (const edge of graph.edges) {
    if (edge.type !== "Contains" || !segmentsById.has(edge.from_id)) continue;
    const host = nodesById.get(edge.to_id);
    if (host?.type === "Host") segmentIdByHostId.set(host.id, edge.from_id);
  }

  const hosts = graph.nodes.flatMap((node): NetworkHost[] => {
    if (node.type !== "Host") return [];
    const services = (servicesByHostId.get(node.id) ?? []).map((service) => ({
      node: service,
      vulnerabilities: vulnerabilitiesByServiceId.get(service.id) ?? [],
    }));
    return [
      {
        id: node.id,
        node,
        segmentId: segmentIdByHostId.get(node.id) ?? "unassigned",
        services,
      },
    ];
  });

  const segments = new Map<string, NetworkSegment>();
  for (const segment of segmentsById.values()) {
    segments.set(segment.id, {
      id: segment.id,
      name: segment.data.name,
      cidr: segment.data.cidr,
      node: segment,
      hosts: [],
      position: {
        x: segment.view_data.x_pos,
        y: segment.view_data.y_pos,
      },
    });
  }
  segments.set("unassigned", {
    id: "unassigned",
    name: "Unassigned",
    hosts: [],
    position: { x: 0, y: 0 },
  });
  for (const host of hosts) {
    const segment = segments.get(host.segmentId)!;
    segment.hosts.push(host);
  }
  const unassigned = segments.get("unassigned")!;
  if (unassigned.hosts.length > 0) {
    unassigned.position = {
      x:
        unassigned.hosts.reduce(
          (sum, host) => sum + host.node.view_data.x_pos,
          0,
        ) / unassigned.hosts.length,
      y:
        unassigned.hosts.reduce(
          (sum, host) => sum + host.node.view_data.y_pos,
          0,
        ) / unassigned.hosts.length,
    };
  }

  const segmentLinksById = new Map<string, NetworkSegmentLink>();
  for (const edge of graph.edges) {
    if (edge.type !== "SegmentReachability") continue;
    const source = nodesById.get(edge.from_id);
    const target = nodesById.get(edge.to_id);
    if (source?.type !== "NetworkSegment" || target?.type !== "NetworkSegment")
      continue;
    if (edge.from_id === edge.to_id) continue;
    const id = `${edge.from_id}:${edge.to_id}`;
    const segmentLink = segmentLinksById.get(id) ?? {
      id,
      sourceId: edge.from_id,
      targetId: edge.to_id,
      edgeIds: [],
    };
    segmentLink.edgeIds.push(edge.id);
    segmentLinksById.set(id, segmentLink);
  }

  const operationalFlows: NetworkOperationalFlow[] = [];
  for (const flow of serverFlows ?? []) {
    const source = nodesById.get(flow.from_id);
    const service = nodesById.get(flow.to_id);
    const targetHost = service
      ? nodesById.get(ownership.get(service.id)!)
      : undefined;
    if (source?.type !== "Host" || service?.type !== "Service") continue;
    if (targetHost?.type !== "Host") continue;
    operationalFlows.push({
      id: flow.id,
      sourceId: source.id,
      sourceName: source.data.name,
      sourcePosition: { x: source.view_data.x_pos, y: source.view_data.y_pos },
      targetId: targetHost.id,
      targetPosition: {
        x: targetHost.view_data.x_pos,
        y: targetHost.view_data.y_pos,
      },
      serviceId: service.id,
      serviceName: service.data.name,
    });
  }

  return {
    hosts,
    segments: [...segments.values()].filter(
      (segment) => segment.hosts.length > 0 || segment.node,
    ),
    segmentLinks: [...segmentLinksById.values()],
    operationalFlows,
  };
}
