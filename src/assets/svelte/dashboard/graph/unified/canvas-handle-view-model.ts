import type { Point } from "../canvas/canvasState";
import { NODE_WIDTH } from "../canvas/geometry";
import type { TopologyHostNode, TopologyServiceNode } from "../topology-scene";
import type { Size } from "./canvas-geometry";
import type { TopologyHostView } from "./canvas-spatial-view-model";
import type { TopologyDetailLevel } from "./semantic-zoom";

export type TopologyConnectionHandleSide = "right";

export interface TopologyConnectionHandleView {
  key: string;
  node: TopologyHostNode | TopologyServiceNode;
  position: Point;
  side: TopologyConnectionHandleSide;
  width: number;
  offset: number;
}

export interface TopologyConnectionHandleOptions {
  detail: TopologyDetailLevel;
  revealsHost: (entityId: string) => boolean;
  revealsService: (entityId: string) => boolean;
  serviceSize: Size;
  hostGlyphHeight: number;
}

/**
 * Builds connection controls for disclosed, placed hosts and services.
 *
 * The canvas owns gesture callbacks. This view model contains only data that
 * determines each control's identity and geometry.
 */
export function buildTopologyConnectionHandles(
  hostViews: readonly TopologyHostView[],
  options: TopologyConnectionHandleOptions,
): TopologyConnectionHandleView[] {
  const handles: TopologyConnectionHandleView[] = [];
  const hostOffset =
    options.detail === "near" ? 36 : options.hostGlyphHeight / 2;

  for (const view of hostViews) {
    if (!options.revealsHost(view.host.id)) continue;
    handles.push({
      key: `host:${view.host.id}`,
      node: view.host.node,
      position: view.position,
      side: "right",
      width: NODE_WIDTH,
      offset: hostOffset,
    });

    for (const service of view.services) {
      if (!options.revealsService(service.scene.id)) continue;
      handles.push({
        key: `service:${service.scene.id}`,
        node: service.scene.node,
        position: service.position,
        side: "right",
        width: options.serviceSize.width,
        offset: options.serviceSize.height / 2,
      });
    }
  }

  return handles;
}
