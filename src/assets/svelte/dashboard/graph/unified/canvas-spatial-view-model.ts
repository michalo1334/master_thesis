import type { Node } from "../../../contracts.generated/graph";
import type { Point } from "../canvas/canvasState";
import { NODE_HEIGHT, NODE_WIDTH } from "../canvas/geometry";
import type {
  TopologyHostScene,
  TopologyScene,
  TopologyServiceScene,
  TopologyUnplacedEntry,
} from "../topology-scene";
import type { TopologySceneIndex } from "../topology-scene-index";
import { frameRect, nodeRect, type Rect, type Size } from "./canvas-geometry";
import type { TopologyLayout } from "./layout";

export interface TopologyServiceView {
  scene: TopologyServiceScene;
  position: Point;
}

/** A placed host with its placed services in projected order. */
export interface TopologyHostView {
  host: TopologyHostScene;
  position: Point;
  services: readonly TopologyServiceView[];
}

/** Entity that the projection cannot place but the canvas can still draw. */
export interface TopologyUnplacedFloater {
  entry: TopologyUnplacedEntry;
  node: Node;
  position: Point;
}

export interface TopologySpatialViewOptions {
  serviceSize: Size;
  contextSize: Size;
  unplacedCardHeight: number;
}

export interface TopologySpatialView {
  /** Frames, projected members, and placed attachments. */
  nodeRects: ReadonlyMap<string, Rect>;
  /** Every drawn entity, including authored-position Unplaced floaters. */
  entityRects: ReadonlyMap<string, Rect>;
  /** Placed host rows with their placed service rows. */
  hostViews: readonly TopologyHostView[];
  unplacedFloaters: readonly TopologyUnplacedFloater[];
}

/**
 * Builds canvas spatial data from the indexed projection and layout output.
 *
 * The index preserves projected traversal order. Missing layout positions stay
 * absent, so semantic zoom and focus disclosure keep their existing behavior.
 */
export function buildTopologySpatialView(
  scene: TopologyScene,
  index: TopologySceneIndex,
  layout: TopologyLayout,
  options: TopologySpatialViewOptions,
): TopologySpatialView {
  const nodeRects = buildNodeRects(scene, index, layout, options);
  const unplacedFloaters = buildUnplacedFloaters(scene, nodeRects);
  const entityRects = buildEntityRects(
    nodeRects,
    unplacedFloaters,
    options.unplacedCardHeight,
  );

  return {
    nodeRects,
    entityRects,
    hostViews: buildHostViews(index, layout),
    unplacedFloaters,
  };
}

function buildNodeRects(
  scene: TopologyScene,
  index: TopologySceneIndex,
  layout: TopologyLayout,
  options: TopologySpatialViewOptions,
): Map<string, Rect> {
  const rects = new Map<string, Rect>();

  for (const entity of index.projectedEntities) {
    const position = layout.positions.get(entity.id);
    if (entity.kind === "segment") {
      const frame = layout.frames.get(entity.id);
      if (frame) rects.set(entity.id, frameRect(frame));
      continue;
    }
    if (!position) continue;
    rects.set(
      entity.id,
      nodeRect(
        position,
        entity.kind === "host"
          ? { width: NODE_WIDTH, height: NODE_HEIGHT }
          : options.serviceSize,
      ),
    );
  }

  for (const attachment of scene.attachments) {
    const position = layout.positions.get(attachment.id);
    if (position)
      rects.set(attachment.id, nodeRect(position, options.contextSize));
  }

  return rects;
}

function buildHostViews(
  index: TopologySceneIndex,
  layout: TopologyLayout,
): TopologyHostView[] {
  const servicesByHostId = new Map<string, TopologyServiceView[]>();

  for (const service of index.services) {
    const position = layout.positions.get(service.id);
    if (!position) continue;
    const services = servicesByHostId.get(service.host.id) ?? [];
    services.push({ scene: service.service, position });
    servicesByHostId.set(service.host.id, services);
  }

  return index.hosts.flatMap((host) => {
    const position = layout.positions.get(host.id);
    return position
      ? [
          {
            host: host.host,
            position,
            services: servicesByHostId.get(host.id) ?? [],
          },
        ]
      : [];
  });
}

function buildUnplacedFloaters(
  scene: TopologyScene,
  nodeRects: ReadonlyMap<string, Rect>,
): TopologyUnplacedFloater[] {
  return scene.unplaced.flatMap((entry) => {
    if (!entry.node || nodeRects.has(entry.entityId)) return [];
    return [
      {
        entry,
        node: entry.node,
        position: {
          x: entry.node.view_data.x_pos,
          y: entry.node.view_data.y_pos,
        },
      },
    ];
  });
}

function buildEntityRects(
  nodeRects: ReadonlyMap<string, Rect>,
  unplacedFloaters: readonly TopologyUnplacedFloater[],
  unplacedCardHeight: number,
): Map<string, Rect> {
  const rects = new Map<string, Rect>(nodeRects);
  for (const floater of unplacedFloaters) {
    rects.set(
      floater.entry.entityId,
      nodeRect(floater.position, {
        width: NODE_WIDTH,
        height: unplacedCardHeight,
      }),
    );
  }
  return rects;
}
