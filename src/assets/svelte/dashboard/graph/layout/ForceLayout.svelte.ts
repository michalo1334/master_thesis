import {
  forceSimulation,
  forceLink,
  forceManyBody,
  forceCenter,
  forceCollide,
} from "d3-force";
import type { SimulationNodeDatum, SimulationLinkDatum } from "d3-force";
import { SvelteMap } from "svelte/reactivity";
import type { Node, Edge } from "../../contract";
import type { ForceParams } from "./ForceLayout.types";
import { resolveOwnership } from "../ownership";

interface SimNode extends SimulationNodeDatum {
  id: string;
  radius: number;
}

/** Strength of child attraction to its immediate owner. */
const OWNERSHIP_STRENGTH = 1.0;

interface SimLink extends SimulationLinkDatum<SimNode> {
  source: string | number | SimNode;
  target: string | number | SimNode;
  distance: number;
}

const DEFAULT_EDGE_DISTANCES: Record<string, number> = {
  SegmentReachability: 200,
  Runs: 80,
  HasVulnerability: 50,
};

function forceOwnership(
  ownership: ReadonlyMap<string, string>,
  nodesById: ReadonlyMap<string, SimNode>,
): (alpha: number) => void {
  return (alpha) => {
    for (const [childId, parentId] of ownership) {
      const child = nodesById.get(childId);
      const parent = nodesById.get(parentId);
      if (!child || !parent) continue;

      child.vx =
        (child.vx ?? 0) +
        ((parent.x ?? 0) - (child.x ?? 0)) * OWNERSHIP_STRENGTH * alpha;
      child.vy =
        (child.vy ?? 0) +
        ((parent.y ?? 0) - (child.y ?? 0)) * OWNERSHIP_STRENGTH * alpha;
    }
  };
}

export function applyForceLayout(
  nodes: Node[],
  edges: Edge[],
  params: ForceParams,
): void {
  if (nodes.length === 0) return;

  const simNodes: SimNode[] = nodes.map((n) => ({
    id: n.id,
    x: n.view_data.x_pos,
    y: n.view_data.y_pos,
    radius: n.view_data.radius ?? params.collisionRadius,
  }));

  const simNodesById = new SvelteMap(simNodes.map((node) => [node.id, node]));
  const ownership = resolveOwnership(nodes, edges);
  const simLinks: SimLink[] = edges
    .filter(
      (edge) => simNodesById.has(edge.from_id) && simNodesById.has(edge.to_id),
    )
    .map((edge) => ({
      source: edge.from_id,
      target: edge.to_id,
      distance: DEFAULT_EDGE_DISTANCES[edge.type] ?? params.linkDistance,
    }))
    .filter((edge) => edge.source !== edge.target);

  const simulation = forceSimulation<SimNode>(simNodes)
    .force(
      "link",
      forceLink<SimNode, SimLink>(simLinks)
        .id((d) => d.id)
        .distance((d) => d.distance),
    )
    .force("charge", forceManyBody<SimNode>().strength(params.repulsion))
    .force("center", forceCenter<SimNode>().strength(params.centerStrength))
    .force(
      "collide",
      forceCollide<SimNode>().radius((d) => d.radius),
    )
    .force("ownership", forceOwnership(ownership, simNodesById))
    .alphaDecay(params.alphaDecay)
    .stop();

  while (simulation.alpha() > simulation.alphaMin()) {
    simulation.tick();
  }

  for (const simNode of simNodes) {
    const node = nodes.find((n) => n.id === simNode.id);
    if (node) {
      node.view_data.x_pos = simNode.x ?? node.view_data.x_pos;
      node.view_data.y_pos = simNode.y ?? node.view_data.y_pos;
    }
  }
}
