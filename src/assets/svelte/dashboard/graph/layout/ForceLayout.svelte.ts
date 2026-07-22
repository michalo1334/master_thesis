import {
  forceSimulation,
  forceLink,
  forceManyBody,
  forceCenter,
  forceCollide,
  forceX,
  forceY,
} from "d3-force";
import type { SimulationNodeDatum, SimulationLinkDatum } from "d3-force";
import type { Node, Edge } from "../../contract";
import type { ForceParams } from "./ForceLayout.types";

interface SimNode extends SimulationNodeDatum {
  id: string;
  type: string;
  radius: number;
}

/** Strength of type-based cluster attraction relative to other forces. */
const CLUSTER_STRENGTH = 1.0;

interface SimLink extends SimulationLinkDatum<SimNode> {
  source: string | number | SimNode;
  target: string | number | SimNode;
  distance: number;
}

const DEFAULT_EDGE_DISTANCES: Record<string, number> = {
  NetworkReachability: 200,
  Runs: 80,
  HasVulnerability: 50,
};

export function applyForceLayout(
  nodes: Node[],
  edges: Edge[],
  params: ForceParams,
): void {
  if (nodes.length === 0) return;

  const simNodes: SimNode[] = nodes.map((n) => ({
    id: n.id,
    type: n.type,
    x: n.view_data.x_pos,
    y: n.view_data.y_pos,
    radius: n.view_data.radius ?? params.collisionRadius,
  }));

  const simLinks: SimLink[] = edges.map((e) => ({
    source: e.from_id,
    target: e.to_id,
    distance: DEFAULT_EDGE_DISTANCES[e.type] ?? params.linkDistance,
  }));

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
    );

  // Type-based clustering: assign each unique node type a deterministic
  // anchor position around the origin, then pull nodes toward their type anchor.
  const types = [...new Set(nodes.map((n) => n.type))].sort();
  const anchors = new Map<string, { cx: number; cy: number }>();

  for (let i = 0; i < types.length; i++) {
    const angle = (2 * Math.PI * i) / types.length;
    anchors.set(types[i], {
      cx: Math.cos(angle) * params.linkDistance * 3,
      cy: Math.sin(angle) * params.linkDistance * 3,
    });
  }

  simulation
    .force(
      "cluster_x",
      forceX<SimNode>((d) => anchors.get(d.type)!.cx).strength(
        CLUSTER_STRENGTH,
      ),
    )
    .force(
      "cluster_y",
      forceY<SimNode>((d) => anchors.get(d.type)!.cy).strength(
        CLUSTER_STRENGTH,
      ),
    )
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
