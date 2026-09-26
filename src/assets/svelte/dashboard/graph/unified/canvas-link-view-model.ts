import type { Edge, Node } from "../../../contracts.generated/graph";
import type { Point } from "../canvas/canvasState";
import type { TopologyScene } from "../topology-scene";
import type { TopologySceneIndex } from "../topology-scene-index";
import type { CanvasEdgeAppearance } from "../canvas/appearance";
import { connectRects, type Rect } from "./canvas-geometry";
import type { TopologyUnplacedFloater } from "./canvas-spatial-view-model";

export interface StructuralLinkPresentation {
  color: string;
  dashArray: string | null;
  label?: (edge: Edge) => string;
}

/** Authored service-ownership connector for a projected host-service pair. */
export interface TopologyStructuralLink {
  edge: Edge;
  sourceRect: Rect;
  targetRect: Rect;
  label: string;
  color: string | undefined;
  dash: string | null;
  appearance: CanvasEdgeAppearance | undefined;
}

/** Focused attachment connector between an attached context entity and its anchor. */
export interface TopologyContextLink {
  key: string;
  attachmentId: string;
  path: { source: Point; target: Point };
  label: string;
}

export interface StructuralLinkOptions {
  edgePresentation: (
    edge: Edge,
  ) => StructuralLinkPresentation | null | undefined;
  edgeAppearance?: (edge: Edge) => CanvasEdgeAppearance | undefined;
}

export interface ContextLinkOptions {
  lensActive: boolean;
  visibleIds: ReadonlySet<string>;
  entityRects: ReadonlyMap<string, Rect>;
  entityLabel: (node: Node) => string;
}

/** Indexes authored `Runs` edges by their direction and endpoints. */
export function indexRunsEdges(
  edges: readonly Edge[],
): ReadonlyMap<string, Edge> {
  const runsEdges = new Map<string, Edge>();
  for (const edge of edges) {
    if (edge.type !== "Runs") continue;
    const key = runsEdgeKey(edge.from_id, edge.to_id);
    if (!runsEdges.has(key)) runsEdges.set(key, edge);
  }
  return runsEdges;
}

/**
 * Builds ownership connectors from projected host-service membership.
 *
 * The projection determines which host-service pairs can connect. An authored
 * `Runs` edge supplies the connector identity and appearance. Raw graph edges
 * never introduce membership, and `Contains` edges are not considered.
 */
export function buildStructuralLinks(
  index: TopologySceneIndex,
  nodeRects: ReadonlyMap<string, Rect>,
  runsEdges: ReadonlyMap<string, Edge>,
  options: StructuralLinkOptions,
): TopologyStructuralLink[] {
  return index.services.flatMap((service) => {
    const sourceRect = nodeRects.get(service.host.id);
    const targetRect = nodeRects.get(service.id);
    const edge = runsEdges.get(runsEdgeKey(service.host.id, service.id));
    if (!sourceRect || !targetRect || edge?.type !== "Runs") return [];

    const presentation = options.edgePresentation(edge);
    return [
      {
        edge,
        sourceRect,
        targetRect,
        label: presentation?.label?.(edge) ?? edge.type,
        color: presentation?.color,
        dash: presentation?.dashArray ?? null,
        appearance: options.edgeAppearance?.(edge),
      },
    ];
  });
}

/**
 * Builds connectors for attachments the active lens reveals.
 *
 * The builder follows accepted projection anchors only. It uses supplied entity
 * rectangles and labels, so the canvas keeps geometry and presentation state at
 * its render boundary.
 */
export function buildContextLinks(
  scene: TopologyScene,
  options: ContextLinkOptions,
): TopologyContextLink[] {
  if (!options.lensActive) return [];

  return scene.attachments.flatMap((attachment) => {
    if (!options.visibleIds.has(attachment.id)) return [];
    const sourceRect = options.entityRects.get(attachment.id);
    if (!sourceRect) return [];

    return attachment.anchors.flatMap((anchor) => {
      const targetRect = options.entityRects.get(anchor.node.id);
      if (!targetRect) return [];
      return [
        {
          key: `${attachment.id}:${anchor.edge.id}`,
          attachmentId: attachment.id,
          path: connectRects(sourceRect, targetRect),
          label: `${anchor.anchor.relationship_type} anchor to ${options.entityLabel(anchor.node)}`,
        },
      ];
    });
  });
}

/**
 * Collects entities that remain valid canvas focus targets.
 *
 * Projected IDs cover topology membership. Attachment IDs and authored-position
 * Unplaced floaters are added because the canvas draws them outside that tree.
 */
export function buildDrawnEntityIds(
  projectedEntityIds: ReadonlySet<string>,
  attachmentIds: readonly string[],
  unplacedFloaters: readonly TopologyUnplacedFloater[],
): Set<string> {
  return new Set([
    ...projectedEntityIds,
    ...attachmentIds,
    ...unplacedFloaters.map((floater) => floater.node.id),
  ]);
}

function runsEdgeKey(fromId: string, toId: string): string {
  return `Runs:${fromId}:${toId}`;
}
