import type {
  Edge,
  LoadedGraph,
  NetworkSegmentNode,
  Node,
} from "../../contract";

export interface NetworkHost {
  id: string;
  node: Extract<Node, { type: "Host" }>;
  segmentId: string;
  services: Array<{
    node: Extract<Node, { type: "Service" }>;
    vulnerabilities: Extract<Node, { type: "Vulnerability" }>[];
  }>;
}

export interface NetworkLink {
  id: string;
  sourceId: string;
  targetId: string;
  edgeIds: string[];
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
  edgeCount: number;
}

export interface NetworkProjection {
  hosts: NetworkHost[];
  links: NetworkLink[];
  segments: NetworkSegment[];
  segmentLinks: NetworkSegmentLink[];
}

function uniqueParents(
  edges: readonly Edge[],
  parentType: Node["type"],
  childType: Node["type"],
  nodesById: ReadonlyMap<string, Node>,
): Map<string, string> {
  const candidates = new Map<string, Set<string>>();
  for (const edge of edges) {
    const parent = nodesById.get(edge.from_id);
    const child = nodesById.get(edge.to_id);
    if (
      !parent ||
      !child ||
      parent.type !== parentType ||
      child.type !== childType
    )
      continue;
    const parentIds = candidates.get(child.id) ?? new Set<string>();
    parentIds.add(parent.id);
    candidates.set(child.id, parentIds);
  }

  return new Map(
    [...candidates].flatMap(([childId, parentIds]) =>
      parentIds.size === 1 ? [[childId, parentIds.values().next().value!]] : [],
    ),
  );
}

export function projectNetwork(graph: LoadedGraph): NetworkProjection {
  const nodesById = new Map(graph.nodes.map((node) => [node.id, node]));
  const servicesByHostId = new Map<
    string,
    Extract<Node, { type: "Service" }>[]
  >();
  const vulnerabilitiesByServiceId = new Map<
    string,
    Extract<Node, { type: "Vulnerability" }>[]
  >();
  const serviceHostIds = uniqueParents(
    graph.edges.filter((edge) => edge.type === "Runs"),
    "Host",
    "Service",
    nodesById,
  );
  const vulnerabilityServiceIds = uniqueParents(
    graph.edges.filter((edge) => edge.type === "HasVulnerability"),
    "Service",
    "Vulnerability",
    nodesById,
  );

  for (const node of graph.nodes) {
    if (node.type === "Service") {
      const hostId = serviceHostIds.get(node.id);
      if (hostId)
        (
          servicesByHostId.get(hostId) ??
          servicesByHostId.set(hostId, []).get(hostId)!
        ).push(node);
    }
    if (node.type === "Vulnerability") {
      const serviceId = vulnerabilityServiceIds.get(node.id);
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

  const hostIdFor = (nodeId: string): string | undefined => {
    const node = nodesById.get(nodeId);
    if (node?.type === "Host") return node.id;
    if (node?.type === "Service") return serviceHostIds.get(node.id);
    if (node?.type === "Vulnerability") {
      const serviceId = vulnerabilityServiceIds.get(node.id);
      return serviceId ? serviceHostIds.get(serviceId) : undefined;
    }
    return undefined;
  };
  const linksByHosts = new Map<string, NetworkLink>();
  for (const edge of graph.edges) {
    if (edge.type !== "NetworkReachability") continue;
    const sourceId = hostIdFor(edge.from_id);
    const targetId = hostIdFor(edge.to_id);
    if (!sourceId || !targetId || sourceId === targetId) continue;
    const id = `${sourceId}:${targetId}`;
    const link = linksByHosts.get(id) ?? {
      id,
      sourceId,
      targetId,
      edgeIds: [],
    };
    link.edgeIds.push(edge.id);
    linksByHosts.set(id, link);
  }

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
  for (const link of linksByHosts.values()) {
    const sourceId = segmentIdByHostId.get(link.sourceId) ?? "unassigned";
    const targetId = segmentIdByHostId.get(link.targetId) ?? "unassigned";
    if (sourceId === targetId) continue;
    const id = `${sourceId}:${targetId}`;
    const segmentLink = segmentLinksById.get(id) ?? {
      id,
      sourceId,
      targetId,
      edgeCount: 0,
    };
    segmentLink.edgeCount += link.edgeIds.length;
    segmentLinksById.set(id, segmentLink);
  }

  return {
    hosts,
    links: [...linksByHosts.values()],
    segments: [...segments.values()].filter(
      (segment) => segment.hosts.length > 0 || segment.node,
    ),
    segmentLinks: [...segmentLinksById.values()],
  };
}

export function cullNetworkHosts(
  hosts: readonly NetworkHost[],
  viewport: { width: number; height: number },
  pan: { x: number; y: number },
  zoom: number,
  margin = 180,
  heightFor: (host: NetworkHost) => number = () => 120,
): NetworkHost[] {
  if (!viewport.width || !viewport.height) return [];
  const scale = zoom / 100;
  const left = (-pan.x - margin) / scale;
  const top = (-pan.y - margin) / scale;
  const right = (viewport.width - pan.x + margin) / scale;
  const bottom = (viewport.height - pan.y + margin) / scale;
  return hosts.filter((host) => {
    const { node } = host;
    const { x_pos, y_pos } = node.view_data;
    return (
      x_pos <= right &&
      x_pos + 160 >= left &&
      y_pos <= bottom &&
      y_pos + heightFor(host) >= top
    );
  });
}

export function cullNetworkSegments(
  segments: readonly NetworkSegment[],
  viewport: { width: number; height: number },
  pan: { x: number; y: number },
  zoom: number,
  margin = 180,
): NetworkSegment[] {
  if (!viewport.width || !viewport.height) return [];
  const scale = zoom / 100;
  const left = (-pan.x - margin) / scale;
  const top = (-pan.y - margin) / scale;
  const right = (viewport.width - pan.x + margin) / scale;
  const bottom = (viewport.height - pan.y + margin) / scale;
  return segments.filter(
    ({ position }) =>
      position.x <= right &&
      position.x + 180 >= left &&
      position.y <= bottom &&
      position.y + 80 >= top,
  );
}
