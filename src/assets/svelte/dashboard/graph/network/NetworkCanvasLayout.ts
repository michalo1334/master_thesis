import type { GraphContract, Node } from "../../../contracts.generated/graph";
import {
  forceCollide,
  forceLink,
  forceManyBody,
  forceSimulation,
  forceX,
  forceY,
} from "d3-force";
export interface ZonePosition {
  x: number;
  y: number;
}

interface LayoutNode {
  id: string;
  x: number;
  y: number;
}

const ZONE_RADIUS = 155;
const HOST_RADIUS = 90;

/** Returns a graph with a persisted, readable network arrangement. */
export function arrangeNetwork(graph: GraphContract): GraphContract {
  const zones = graph.nodes.filter(
    (node): node is Extract<Node, { type: "NetworkSegment" }> =>
      node.type === "NetworkSegment",
  );
  const zoneNodes: LayoutNode[] = zones.map((zone) => ({
    id: zone.id,
    x: zone.view_data.x_pos,
    y: zone.view_data.y_pos,
  }));
  const zoneIds = new Set(zones.map((zone) => zone.id));
  const links = graph.edges
    .filter(
      (edge) =>
        edge.type === "SegmentReachability" &&
        zoneIds.has(edge.from_id) &&
        zoneIds.has(edge.to_id),
    )
    .map((edge) => ({ source: edge.from_id, target: edge.to_id }));

  forceSimulation(zoneNodes)
    .force("charge", forceManyBody<LayoutNode>().strength(-260))
    .force("collide", forceCollide<LayoutNode>(ZONE_RADIUS).iterations(2))
    .force(
      "link",
      forceLink<LayoutNode, (typeof links)[number]>(links)
        .id((node) => node.id)
        .distance(360)
        .strength(0.08),
    )
    .stop()
    .tick(160);

  const zonePosition = new Map(zoneNodes.map((zone) => [zone.id, zone]));
  const hostZone = new Map<string, string>();
  for (const edge of graph.edges) {
    if (edge.type === "Contains" && zoneIds.has(edge.from_id))
      hostZone.set(edge.to_id, edge.from_id);
  }
  const hosts = graph.nodes.filter(
    (node): node is Extract<Node, { type: "Host" }> => node.type === "Host",
  );
  const hostNodes: LayoutNode[] = hosts.map((host) => ({
    id: host.id,
    x: host.view_data.x_pos,
    y: host.view_data.y_pos,
  }));
  forceSimulation(hostNodes)
    .force("charge", forceManyBody<LayoutNode>().strength(-140))
    .force("collide", forceCollide<LayoutNode>(HOST_RADIUS).iterations(2))
    .force(
      "x",
      forceX<LayoutNode>(
        (host) => zonePosition.get(hostZone.get(host.id) ?? "")?.x ?? 0,
      ).strength(0.08),
    )
    .force(
      "y",
      forceY<LayoutNode>(
        (host) => zonePosition.get(hostZone.get(host.id) ?? "")?.y ?? 0,
      ).strength(0.08),
    )
    .stop()
    .tick(180);

  const position = new Map(
    [...zoneNodes, ...hostNodes].map((node) => [node.id, node]),
  );
  return {
    ...graph,
    nodes: graph.nodes.map((node) => {
      const next = position.get(node.id);
      return next
        ? {
            ...node,
            view_data: { ...node.view_data, x_pos: next.x, y_pos: next.y },
          }
        : node;
    }),
  };
}
