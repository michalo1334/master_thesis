import { NODE_HEIGHT, NODE_WIDTH } from "../canvas/geometry";
import type {
  TopologyAttachmentAnchorScene,
  TopologyAttachmentScene,
  TopologyScene,
  TopologySegmentScene,
} from "../topology-scene";

export interface Point {
  x: number;
  y: number;
}

export interface Size {
  width: number;
  height: number;
}

export interface Rect extends Point, Size {}

export interface TopologySegmentFrame {
  id: string;
  /** World-space top-left corner of the segment footprint. */
  position: Point;
  /** Tight footprint that contains the packed members. */
  size: Size;
}

export interface TopologyLayout {
  /**
   * World position for every host, service, attached-context, and segment node.
   * Segment positions are frame anchors, so persisting this map keeps the
   * arranged frames after a reload. Segment nodes render through their frame.
   */
  positions: Map<string, Point>;
  /** Segment footprints. Segment nodes render through their frame. */
  frames: Map<string, TopologySegmentFrame>;
}

export interface MeasureTopologyOptions {
  /**
   * Attached-context positions to reuse instead of deriving them again.
   *
   * A geometry drag freezes these, so attached context keeps its world position
   * while members move and the ring search does not run again per drag frame.
   */
  freezeContextPositions?: ReadonlyMap<string, Point>;
}

export const SEGMENT_HEADER_HEIGHT = 44;
export const SEGMENT_PADDING = 24;
export const SEGMENT_GAP = 64;
export const HOST_GAP = 20;
export const SERVICE_GAP = 8;
export const SERVICE_SIZE: Size = { width: NODE_WIDTH, height: 32 };
export const CONTEXT_SIZE: Size = { width: 168, height: NODE_HEIGHT };
const NODE_SIZE: Size = { width: NODE_WIDTH, height: NODE_HEIGHT };
export const CONTEXT_GAP = 28;
export const MIN_SEGMENT_WIDTH = 280;
export const MIN_SEGMENT_HEIGHT =
  SEGMENT_HEADER_HEIGHT + 2 * SEGMENT_PADDING + NODE_HEIGHT;
/** Width at which Arrange starts a new segment row. */
export const ARRANGE_ROW_WIDTH = 1600;

const MAX_RING = 12;

interface PackedMember {
  /** Host offset from the segment frame origin. */
  offset: Point;
  /** Service offsets from the segment frame origin. */
  services: Point[];
}

export interface PackedSegment {
  size: Size;
  members: PackedMember[];
}

/**
 * Packs hosts and services into a tight rectangular grid.
 *
 * The result is independent of world coordinates, so it is a function of
 * membership and counts only.
 */
export function packSegment(segment: TopologySegmentScene): PackedSegment {
  const hostCount = segment.hosts.length;
  const maxServices = segment.hosts.reduce(
    (max, host) => Math.max(max, host.services.length),
    0,
  );
  const cellHeight =
    NODE_HEIGHT + maxServices * (SERVICE_SIZE.height + SERVICE_GAP);
  const columns = hostCount === 0 ? 1 : Math.ceil(Math.sqrt(hostCount));
  const rows = hostCount === 0 ? 0 : Math.ceil(hostCount / columns);
  const contentWidth =
    hostCount === 0 ? 0 : columns * NODE_WIDTH + (columns - 1) * HOST_GAP;
  const contentHeight =
    hostCount === 0 ? 0 : rows * cellHeight + (rows - 1) * HOST_GAP;

  const size: Size = {
    width: Math.max(MIN_SEGMENT_WIDTH, contentWidth + 2 * SEGMENT_PADDING),
    height: Math.max(
      MIN_SEGMENT_HEIGHT,
      SEGMENT_HEADER_HEIGHT + 2 * SEGMENT_PADDING + contentHeight,
    ),
  };

  const available = size.width - 2 * SEGMENT_PADDING;
  const originX = SEGMENT_PADDING + Math.max(0, (available - contentWidth) / 2);
  const originY = SEGMENT_HEADER_HEIGHT + SEGMENT_PADDING;

  const members = segment.hosts.map((host, index) => {
    const offset = {
      x: originX + (index % columns) * (NODE_WIDTH + HOST_GAP),
      y: originY + Math.floor(index / columns) * (cellHeight + HOST_GAP),
    };
    const services = host.services.map((_service, serviceIndex) => ({
      x: offset.x,
      y:
        offset.y +
        NODE_HEIGHT +
        SERVICE_GAP +
        serviceIndex * (SERVICE_SIZE.height + SERVICE_GAP),
    }));
    return { offset, services };
  });

  return { size, members };
}

/**
 * Arranges segments into a compact, non-overlapping shelf layout.
 *
 * Segment reading order and the top-left anchor decide row order and the layout
 * origin. Members are packed, so a frame contains no area from old scattered
 * coordinates. Attached context leaves the packed frames and stays outside.
 *
 * `positions` holds every placed entity, including the segment frame anchors, so
 * a caller can persist the result. `measureTopology` then rebuilds the same
 * frames from the persisted graph.
 */
export function arrangeTopology(scene: TopologyScene): TopologyLayout {
  const positions = new Map<string, Point>();
  const frames = new Map<string, TopologySegmentFrame>();

  const packed = scene.segments.map((segment) => ({
    segment,
    packed: packSegment(segment),
  }));
  packed.sort(compareSegmentAnchors);

  const origin = sceneAnchorOrigin(scene);
  let cursorX = origin.x;
  let cursorY = origin.y;
  let rowHeight = 0;
  let rowEmpty = true;

  for (const entry of packed) {
    const fitsRow =
      rowEmpty ||
      cursorX + entry.packed.size.width <= origin.x + ARRANGE_ROW_WIDTH;
    if (!fitsRow) {
      cursorX = origin.x;
      cursorY += rowHeight + SEGMENT_GAP;
      rowHeight = 0;
      rowEmpty = true;
    }

    const position = { x: cursorX, y: cursorY };
    frames.set(entry.segment.id, {
      id: entry.segment.id,
      position,
      size: entry.packed.size,
    });
    writeMemberPositions(positions, entry.segment, entry.packed, position);
    // Persisting this anchor makes `measureTopology` rebuild the same frame, so
    // arranged positions survive a save and reload round trip.
    positions.set(entry.segment.id, {
      x: position.x + SEGMENT_PADDING,
      y: position.y + SEGMENT_PADDING,
    });
    cursorX += entry.packed.size.width + SEGMENT_GAP;
    rowHeight = Math.max(rowHeight, entry.packed.size.height);
    rowEmpty = false;
  }

  placeContext(positions, scene.attachments, frameRects(frames));
  return { positions, frames };
}

/**
 * Measures an authored layout without moving authored node positions.
 *
 * Each frame stays where the graph authors it and grows until it contains its
 * members. The frame reserves a header band above the content. When a member
 * would overlap that band, the frame grows upward instead of moving the member.
 * Attached context leaves the frames and stays outside. A graph that causes
 * collisions or excessive spread becomes visible through its frames instead of
 * being rearranged.
 */
export function measureTopology(
  scene: TopologyScene,
  options: MeasureTopologyOptions = {},
): TopologyLayout {
  const positions = new Map<string, Point>();
  const frames = new Map<string, TopologySegmentFrame>();

  for (const segment of scene.segments) {
    frames.set(segment.id, measureSegmentFrame(segment, positions));
  }

  placeContext(
    positions,
    scene.attachments,
    frameRects(frames),
    options.freezeContextPositions,
  );
  return { positions, frames };
}

/**
 * Measures one authored segment frame and records its member positions.
 *
 * The header band sits at the frame top. Authored members start below
 * `SEGMENT_HEADER_HEIGHT + SEGMENT_PADDING`, so they never overlap it. The
 * segment node anchor stays inside the frame with `SEGMENT_PADDING` clearance.
 * The anchor is recorded in `positions` as well, so an arranged segment node
 * keeps its frame after a reload.
 */
export function measureSegmentFrame(
  segment: TopologySegmentScene,
  positions: Map<string, Point>,
): TopologySegmentFrame {
  const packed = packSegment(segment);
  const anchor = {
    x: segment.node.view_data.x_pos,
    y: segment.node.view_data.y_pos,
  };
  positions.set(segment.id, { ...anchor });
  const members = recordMemberPositions(segment, positions);

  const minX = Math.min(anchor.x, members?.x ?? anchor.x);
  const maxX = Math.max(
    anchor.x,
    members ? members.x + members.width : anchor.x,
  );
  const minY = Math.min(anchor.y, members?.y ?? anchor.y);
  const maxY = Math.max(
    anchor.y,
    members ? members.y + members.height : anchor.y,
  );

  const top = members
    ? Math.min(
        minY - SEGMENT_PADDING,
        members.y - SEGMENT_PADDING - SEGMENT_HEADER_HEIGHT,
      )
    : minY - SEGMENT_PADDING;

  return {
    id: segment.id,
    position: { x: minX - SEGMENT_PADDING, y: top },
    size: {
      width: Math.max(packed.size.width, maxX - minX + 2 * SEGMENT_PADDING),
      height: Math.max(packed.size.height, maxY + SEGMENT_PADDING - top),
    },
  };
}

function frameRects(frames: Map<string, TopologySegmentFrame>): Rect[] {
  return [...frames.values()].map((frame) =>
    toRect(frame.position, frame.size),
  );
}

function writeMemberPositions(
  positions: Map<string, Point>,
  segment: TopologySegmentScene,
  packed: PackedSegment,
  origin: Point,
): void {
  segment.hosts.forEach((host, index) => {
    const member = packed.members[index];
    if (!member) return;
    positions.set(host.id, {
      x: origin.x + member.offset.x,
      y: origin.y + member.offset.y,
    });
    host.services.forEach((service, serviceIndex) => {
      const offset = member.services[serviceIndex];
      if (!offset) return;
      positions.set(service.id, {
        x: origin.x + offset.x,
        y: origin.y + offset.y,
      });
    });
  });
}

/**
 * Records authored host and service positions and returns their envelope.
 * Returns `null` when the segment has no members. The segment anchor is not a
 * member: it stays an authored point of the frame.
 */
function recordMemberPositions(
  segment: TopologySegmentScene,
  positions: Map<string, Point>,
): Rect | null {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;

  const include = (point: Point, size: Size) => {
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x + size.width);
    maxY = Math.max(maxY, point.y + size.height);
  };

  for (const host of segment.hosts) {
    const point = {
      x: host.node.view_data.x_pos,
      y: host.node.view_data.y_pos,
    };
    positions.set(host.id, point);
    include(point, NODE_SIZE);

    for (const service of host.services) {
      const servicePoint = {
        x: service.node.view_data.x_pos,
        y: service.node.view_data.y_pos,
      };
      positions.set(service.id, servicePoint);
      include(servicePoint, SERVICE_SIZE);
    }
  }

  if (!Number.isFinite(minX)) return null;
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

/**
 * Places every attached-context node outside the segment frames, near the
 * centroid of its resolvable anchors.
 */
function placeContext(
  positions: Map<string, Point>,
  attachments: readonly TopologyAttachmentScene[],
  frames: readonly Rect[],
  frozenPositions?: ReadonlyMap<string, Point>,
): void {
  // Frozen rectangles are obstacles for every placement decision, including the
  // decisions that run before the frozen attachment itself is visited.
  const placed: Rect[] = [];
  for (const attachment of attachments) {
    const frozen = frozenPositions?.get(attachment.id);
    if (frozen) placed.push(toRect(frozen, CONTEXT_SIZE));
  }

  for (const attachment of attachments) {
    const frozen = frozenPositions?.get(attachment.id);
    if (frozen) {
      positions.set(attachment.id, { ...frozen });
      continue;
    }

    const anchors = attachment.anchors
      .map((anchor) => anchorCenter(anchor, positions))
      .filter((point): point is Point => point !== null);
    if (anchors.length === 0) continue;

    const centroid = {
      x: anchors.reduce((sum, point) => sum + point.x, 0) / anchors.length,
      y: anchors.reduce((sum, point) => sum + point.y, 0) / anchors.length,
    };

    const outside = pushOutside(centroid, frames, CONTEXT_GAP);
    const slot = findFreeSlot(outside, CONTEXT_SIZE, [...frames, ...placed]);
    positions.set(attachment.id, slot);
    placed.push(toRect(slot, CONTEXT_SIZE));
  }
}

function anchorCenter(
  anchor: TopologyAttachmentAnchorScene,
  positions: Map<string, Point>,
): Point | null {
  const position = positions.get(anchor.anchor.node_id);
  if (!position) return null;
  const size: Size = anchor.node.type === "Service" ? SERVICE_SIZE : NODE_SIZE;
  return {
    x: position.x + size.width / 2,
    y: position.y + size.height / 2,
  };
}

function compareSegmentAnchors(
  a: { segment: TopologySegmentScene },
  b: { segment: TopologySegmentScene },
): number {
  const ay = a.segment.node.view_data.y_pos;
  const by = b.segment.node.view_data.y_pos;
  if (ay !== by) return ay - by;
  const ax = a.segment.node.view_data.x_pos;
  const bx = b.segment.node.view_data.x_pos;
  if (ax !== bx) return ax - bx;
  return compareStrings(a.segment.id, b.segment.id);
}

function compareStrings(a: string, b: string): number {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

function sceneAnchorOrigin(scene: TopologyScene): Point {
  let x = Infinity;
  let y = Infinity;
  for (const segment of scene.segments) {
    x = Math.min(x, segment.node.view_data.x_pos);
    y = Math.min(y, segment.node.view_data.y_pos);
  }
  return Number.isFinite(x) && Number.isFinite(y) ? { x, y } : { x: 0, y: 0 };
}

function toRect(position: Point, size: Size): Rect {
  return { x: position.x, y: position.y, ...size };
}

function inflate(rect: Rect, gap: number): Rect {
  return {
    x: rect.x - gap,
    y: rect.y - gap,
    width: rect.width + 2 * gap,
    height: rect.height + 2 * gap,
  };
}

function overlaps(a: Rect, b: Rect, gap = 0): boolean {
  return (
    a.x < b.x + b.width + gap &&
    b.x < a.x + a.width + gap &&
    a.y < b.y + b.height + gap &&
    b.y < a.y + a.height + gap
  );
}

function contains(rect: Rect, point: Point): boolean {
  return (
    point.x > rect.x &&
    point.x < rect.x + rect.width &&
    point.y > rect.y &&
    point.y < rect.y + rect.height
  );
}

function distance(a: Point, b: Point): number {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
}

/** Moves a point out of every frame, along the shortest deterministic escape. */
function pushOutside(
  point: Point,
  frames: readonly Rect[],
  gap: number,
): Point {
  let current = { ...point };

  for (let pass = 0; pass <= frames.length; pass++) {
    const blocker = frames.find((frame) =>
      contains(inflate(frame, gap), current),
    );
    if (!blocker) break;
    const bounds = inflate(blocker, gap);
    const escapes: Point[] = [
      { x: bounds.x, y: current.y },
      { x: bounds.x + bounds.width, y: current.y },
      { x: current.x, y: bounds.y },
      { x: current.x, y: bounds.y + bounds.height },
    ];
    current = escapes.reduce((best, candidate) =>
      distance(candidate, current) <= distance(best, current)
        ? candidate
        : best,
    );
  }

  return current;
}

/**
 * Finds the nearest free slot around a point. Candidates use deterministic ring
 * offsets, so identical input produces identical output.
 */
function findFreeSlot(
  point: Point,
  size: Size,
  obstacles: readonly Rect[],
): Point {
  const stepX = size.width + CONTEXT_GAP;
  const stepY = size.height + CONTEXT_GAP;

  for (const offset of ringOffsets()) {
    const candidate = {
      x: point.x + offset.x * stepX,
      y: point.y + offset.y * stepY,
    };
    const rect = toRect(candidate, size);
    if (!obstacles.some((obstacle) => overlaps(rect, obstacle, CONTEXT_GAP))) {
      return candidate;
    }
  }

  let rightmost = point.x;
  for (const obstacle of obstacles) {
    rightmost = Math.max(rightmost, obstacle.x + obstacle.width + CONTEXT_GAP);
  }
  return { x: rightmost, y: point.y };
}

let cachedRingOffsets: Point[] | undefined;

function ringOffsets(): readonly Point[] {
  if (cachedRingOffsets) return cachedRingOffsets;

  const offsets: Point[] = [{ x: 0, y: 0 }];
  for (let ring = 1; ring <= MAX_RING; ring++) {
    for (let y = -ring; y <= ring; y++) {
      for (let x = -ring; x <= ring; x++) {
        if (Math.max(Math.abs(x), Math.abs(y)) === ring) {
          offsets.push({ x, y });
        }
      }
    }
  }
  cachedRingOffsets = offsets;
  return offsets;
}
