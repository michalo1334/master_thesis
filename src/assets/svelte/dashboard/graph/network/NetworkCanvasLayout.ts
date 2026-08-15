import { forceCollide, forceLink, forceSimulation } from "d3-force";

export interface ZonePosition {
  x: number;
  y: number;
}

export interface ZoneLayoutInput {
  id: string;
  position: ZonePosition;
  radius: { x: number; y: number };
  pinned?: boolean;
}

export interface ZoneLayoutLink {
  sourceId: string;
  targetId: string;
}

export interface HostCardLayoutInput {
  id: string;
  height: number;
}

interface LayoutNode extends ZoneLayoutInput {
  x: number;
  y: number;
  fx?: number;
  fy?: number;
}

const GAP = 24;
const HOST_COLUMN_GAP = 14;
const HOST_ROW_GAP = 14;
const HOST_WIDTH = 128;

export function zoneCollisionRadius(zone: ZoneLayoutInput): number {
  return Math.max(zone.radius.x, zone.radius.y) + GAP / 2;
}

export function layoutHostCards(
  center: ZonePosition,
  cards: readonly HostCardLayoutInput[],
  columns = Math.min(3, Math.max(1, Math.ceil(Math.sqrt(cards.length)))),
): Map<string, ZonePosition> {
  if (!cards.length) return new Map();
  const rows = Array.from(
    { length: Math.ceil(cards.length / columns) },
    () => 0,
  );
  for (const [index, card] of cards.entries()) {
    const row = Math.floor(index / columns);
    rows[row] = Math.max(rows[row]!, card.height);
  }
  const totalHeight =
    rows.reduce((height, rowHeight) => height + rowHeight, 0) +
    HOST_ROW_GAP * (rows.length - 1);
  const rowTops: number[] = [];
  let y = center.y - totalHeight / 2;
  for (const height of rows) {
    rowTops.push(y);
    y += height + HOST_ROW_GAP;
  }

  return new Map(
    cards.map((card, index) => {
      const column = index % columns;
      const row = Math.floor(index / columns);
      return [
        card.id,
        {
          x:
            center.x +
            (column - (columns - 1) / 2) * (HOST_WIDTH + HOST_COLUMN_GAP),
          y: rowTops[row]! + card.height / 2,
        },
      ];
    }),
  );
}

export function layoutZones(
  zones: readonly ZoneLayoutInput[],
  links: readonly ZoneLayoutLink[],
): Map<string, ZonePosition> {
  const nodes: LayoutNode[] = zones.map((zone) => ({
    ...zone,
    position: { ...zone.position },
    x: zone.position.x,
    y: zone.position.y,
    fx: zone.pinned ? zone.position.x : undefined,
    fy: zone.pinned ? zone.position.y : undefined,
  }));
  const knownIds = new Set(nodes.map((node) => node.id));
  const layoutLinks = links
    .filter(
      (link) => knownIds.has(link.sourceId) && knownIds.has(link.targetId),
    )
    .map((link) => ({ source: link.sourceId, target: link.targetId }));
  const simulation = forceSimulation(nodes)
    .force(
      "collide",
      forceCollide<LayoutNode>(zoneCollisionRadius).strength(1).iterations(3),
    )
    .force(
      "link",
      forceLink<LayoutNode, { source: string; target: string }>(layoutLinks)
        .id((node) => node.id)
        .distance(300)
        .strength(0.025),
    )
    .stop();

  simulation.tick(180);
  return new Map(nodes.map((node) => [node.id, { x: node.x, y: node.y }]));
}
