import type { Edge, Node } from "../../../contracts.generated/graph";
import type {
  Attachment,
  Host,
  Segment,
  Service,
} from "../../../contracts.generated/dashboard/graph/topology_projection";
import { describe, expect, it } from "vitest";
import type { TopologyScene } from "../topology-scene";
import { buildTopologyScene } from "../topology-scene";
import {
  anchorRecord,
  attachmentRecord,
  credentialNode,
  graphContract,
  hasVulnerabilityEdge,
  hostNode,
  hostRecord,
  issueRecord,
  missionCapabilityNode,
  projectionOf,
  segmentNode,
  segmentRecord,
  serviceNode,
  serviceRecord,
  storesCredentialEdge,
  supportsEdge,
  vulnerabilityNode,
} from "../__tests__/topology-fixtures";
import { NODE_HEIGHT, NODE_WIDTH } from "../canvas/geometry";
import {
  CONTEXT_GAP,
  CONTEXT_SIZE,
  SEGMENT_GAP,
  SEGMENT_HEADER_HEIGHT,
  SEGMENT_PADDING,
  SERVICE_SIZE,
  arrangeTopology,
  measureTopology,
  measureSegmentFrame,
  packSegment,
  segmentMembers,
} from "./layout";
import { compareStrings } from "./ordering";

interface ServiceSpec {
  id: string;
  x: number;
  y: number;
}

interface HostSpec {
  id: string;
  x: number;
  y: number;
  services?: ServiceSpec[];
}

interface SegmentSpec {
  id: string;
  anchor: { x: number; y: number };
  hosts: HostSpec[];
}

type AttachmentKind = "Vulnerability" | "Credential" | "MissionCapability";

interface AttachmentSpec {
  id: string;
  kind: AttachmentKind;
  anchorNodeIds: string[];
}

interface SceneSpec {
  segments: SegmentSpec[];
  attachments?: AttachmentSpec[];
  unplacedHosts?: Array<{
    id: string;
    x: number;
    y: number;
    services?: ServiceSpec[];
  }>;
}

function buildScene(spec: SceneSpec): TopologyScene {
  const nodes: Node[] = [];
  const edges: Edge[] = [];
  const segments: Segment[] = [];
  const hosts: Host[] = [];
  const services: Service[] = [];

  for (const segment of spec.segments) {
    nodes.push(segmentNode(segment.id, segment.anchor.x, segment.anchor.y));
    const hostIds: string[] = [];
    let serviceCount = 0;

    for (const host of segment.hosts) {
      nodes.push(hostNode(host.id, host.x, host.y));
      const serviceIds: string[] = [];

      for (const service of host.services ?? []) {
        nodes.push(serviceNode(service.id, service.x, service.y));
        services.push(serviceRecord(service.id, host.id));
        serviceIds.push(service.id);
        serviceCount += 1;
      }

      hosts.push(hostRecord(host.id, segment.id, serviceIds));
      hostIds.push(host.id);
    }

    segments.push(
      segmentRecord(segment.id, hostIds, { service_count: serviceCount }),
    );
  }

  const attachments: Attachment[] = [];
  for (const attachment of spec.attachments ?? []) {
    nodes.push(contextNode(attachment.id, attachment.kind));
    const anchors = attachment.anchorNodeIds.map((nodeId, index) => {
      const edgeId = `${attachment.id}-edge-${index}`;
      edges.push(contextEdge(edgeId, attachment.kind, nodeId, attachment.id));
      return anchorRecord(nodeId, edgeId, contextRelationship(attachment.kind));
    });
    attachments.push(attachmentRecord(attachment.id, attachment.kind, anchors));
  }

  for (const host of spec.unplacedHosts ?? []) {
    nodes.push(hostNode(host.id, host.x, host.y));
    for (const service of host.services ?? []) {
      nodes.push(serviceNode(service.id, service.x, service.y));
      services.push(serviceRecord(service.id, host.id));
    }
    hosts.push(hostRecord(host.id, null));
  }

  return buildTopologyScene(
    graphContract(nodes, edges),
    projectionOf({
      segments,
      hosts,
      services,
      attachments,
      issues: (spec.unplacedHosts ?? []).map((host) =>
        issueRecord("host_without_segment", host.id),
      ),
    }),
  );
}

function contextNode(id: string, kind: AttachmentKind): Node {
  switch (kind) {
    case "Vulnerability":
      return vulnerabilityNode(id);
    case "Credential":
      return credentialNode(id);
    default:
      return missionCapabilityNode(id);
  }
}

function contextRelationship(kind: AttachmentKind) {
  switch (kind) {
    case "Vulnerability":
      return "HasVulnerability" as const;
    case "Credential":
      return "StoresCredential" as const;
    default:
      return "Supports" as const;
  }
}

function contextEdge(
  id: string,
  kind: AttachmentKind,
  anchorNodeId: string,
  attachmentId: string,
): Edge {
  switch (kind) {
    case "Vulnerability":
      return hasVulnerabilityEdge(id, anchorNodeId, attachmentId);
    case "Credential":
      return storesCredentialEdge(id, anchorNodeId, attachmentId);
    default:
      return supportsEdge(id, anchorNodeId, attachmentId);
  }
}

interface TestLayout {
  frames: Map<string, { id: string; position: unknown; size: unknown }>;
  positions: Map<string, unknown>;
}

function serialized(layout: TestLayout): string {
  const frames = [...layout.frames.values()]
    .map((frame): [string, unknown, unknown] => [
      frame.id,
      frame.position,
      frame.size,
    ])
    .sort((a, b) => compareStrings(a[0], b[0]));
  const positions = [...layout.positions.entries()].sort((a, b) =>
    compareStrings(a[0], b[0]),
  );
  return JSON.stringify({ frames, positions });
}

interface TestRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** Writes layout positions into the graph nodes, as the document does. */
function persistPositions(
  scene: TopologyScene,
  positions: ReadonlyMap<string, { x: number; y: number }>,
): void {
  const apply = (node: {
    id: string;
    view_data: { x_pos: number; y_pos: number };
  }) => {
    const next = positions.get(node.id);
    if (!next) return;
    node.view_data = { x_pos: next.x, y_pos: next.y };
  };

  for (const segment of scene.segments) {
    apply(segment.node);
    for (const host of segment.hosts) {
      apply(host.node);
      for (const service of host.services) apply(service.node);
    }
  }
  for (const attachment of scene.attachments) apply(attachment.node);
}

function rectOf(
  position: { x: number; y: number },
  size?: { width: number; height: number },
): TestRect {
  const resolved = size ?? { width: NODE_WIDTH, height: NODE_HEIGHT };
  return { x: position.x, y: position.y, ...resolved };
}

function frameRect(frame: {
  position: { x: number; y: number };
  size: { width: number; height: number };
}): TestRect {
  return { x: frame.position.x, y: frame.position.y, ...frame.size };
}

function gaps(a: TestRect, b: TestRect): { x: number; y: number } {
  return {
    x: Math.max(a.x - (b.x + b.width), b.x - (a.x + a.width)),
    y: Math.max(a.y - (b.y + b.height), b.y - (a.y + a.height)),
  };
}

const singleSegment: SceneSpec = {
  segments: [
    {
      id: "segment-1",
      anchor: { x: 40, y: 60 },
      hosts: [
        {
          id: "host-1",
          x: 90,
          y: 150,
          services: [{ id: "service-1", x: 90, y: 240 }],
        },
        { id: "host-2", x: 240, y: 150 },
      ],
    },
  ],
};

describe("segmentMembers", () => {
  it("flattens hosts and services in layout order", () => {
    const scene = buildScene(singleSegment);

    expect(
      segmentMembers(scene.segments[0]!).map((member) => [
        member.id,
        member.hostIndex,
        member.serviceIndex,
      ]),
    ).toEqual([
      ["host-1", 0, null],
      ["service-1", 0, 0],
      ["host-2", 1, null],
    ]);
  });
});

describe("arrangeTopology", () => {
  it("keeps every member inside its segment frame", () => {
    const scene = buildScene({
      segments: [
        singleSegment.segments[0]!,
        {
          id: "segment-2",
          anchor: { x: 400, y: 60 },
          hosts: Array.from({ length: 5 }, (_value, index) => ({
            id: `host-${index + 10}`,
            x: 400 + index,
            y: 200,
            services: [{ id: `service-${index + 10}`, x: 400, y: 300 }],
          })),
        },
      ],
    });

    const layout = arrangeTopology(scene);

    for (const segment of scene.segments) {
      const frame = layout.frames.get(segment.id)!;
      for (const host of segment.hosts) {
        const position = layout.positions.get(host.id)!;
        expect(position.x).toBeGreaterThanOrEqual(frame.position.x);
        expect(position.y).toBeGreaterThanOrEqual(frame.position.y);
        expect(position.x + NODE_WIDTH).toBeLessThanOrEqual(
          frame.position.x + frame.size.width,
        );
        expect(position.y + NODE_HEIGHT).toBeLessThanOrEqual(
          frame.position.y + frame.size.height,
        );

        for (const service of host.services) {
          const servicePosition = layout.positions.get(service.id)!;
          expect(servicePosition.x).toBeGreaterThanOrEqual(frame.position.x);
          expect(servicePosition.y).toBeGreaterThanOrEqual(frame.position.y);
          expect(servicePosition.x + SERVICE_SIZE.width).toBeLessThanOrEqual(
            frame.position.x + frame.size.width,
          );
          expect(servicePosition.y + SERVICE_SIZE.height).toBeLessThanOrEqual(
            frame.position.y + frame.size.height,
          );
        }
      }
    }
  });

  it("keeps segment frames apart", () => {
    const scene = buildScene({
      segments: Array.from({ length: 5 }, (_value, index) => ({
        id: `segment-${index}`,
        anchor: { x: 0, y: 0 },
        hosts: Array.from({ length: index + 1 }, (_host, hostIndex) => ({
          id: `segment-${index}-host-${hostIndex}`,
          x: 0,
          y: 0,
        })),
      })),
    });

    const layout = arrangeTopology(scene);
    const frames = [...layout.frames.values()].map(frameRect);

    for (let a = 0; a < frames.length; a++) {
      for (let b = a + 1; b < frames.length; b++) {
        const gap = gaps(frames[a]!, frames[b]!);
        expect(gap.x >= SEGMENT_GAP - 1e-9 || gap.y >= SEGMENT_GAP - 1e-9).toBe(
          true,
        );
      }
    }
  });

  it("keeps packed members below the segment header band", () => {
    const scene = buildScene({
      segments: [
        {
          id: "segment-1",
          anchor: { x: 0, y: 0 },
          hosts: [
            { id: "host-1", x: 0, y: 0 },
            { id: "host-2", x: 0, y: 0 },
          ],
        },
      ],
    });

    const layout = arrangeTopology(scene);
    const frame = layout.frames.get("segment-1")!;
    const contentTop =
      frame.position.y + SEGMENT_HEADER_HEIGHT + SEGMENT_PADDING;

    for (const host of scene.segments[0]!.hosts) {
      expect(layout.positions.get(host.id)!.y).toBeGreaterThanOrEqual(
        contentTop,
      );
    }
  });

  it("ignores authored member coordinates and input order", () => {
    const authored = buildScene({
      segments: [
        {
          id: "segment-1",
          anchor: { x: 0, y: 0 },
          hosts: [{ id: "host-1", x: 4000, y: 2500 }],
        },
        {
          id: "segment-2",
          anchor: { x: 0, y: 0 },
          hosts: [{ id: "host-2", x: -900, y: 300 }],
        },
      ],
    });
    const packed = buildScene({
      segments: [
        {
          id: "segment-1",
          anchor: { x: 0, y: 0 },
          hosts: [{ id: "host-1", x: 0, y: 0 }],
        },
        {
          id: "segment-2",
          anchor: { x: 0, y: 0 },
          hosts: [{ id: "host-2", x: 0, y: 0 }],
        },
      ],
    });

    const first = arrangeTopology(packed);
    expect(serialized(arrangeTopology(authored))).toBe(serialized(first));
    expect(serialized(arrangeTopology(packed))).toBe(serialized(first));

    const reversed: TopologyScene = {
      ...packed,
      segments: [...packed.segments].reverse(),
    };
    expect(serialized(arrangeTopology(reversed))).toBe(serialized(first));
  });

  it("keeps every attached-context node outside segment bounds", () => {
    const scene = buildScene({
      segments: [
        {
          id: "segment-1",
          anchor: { x: 0, y: 0 },
          hosts: [{ id: "host-1", x: 0, y: 0 }],
        },
        {
          id: "segment-2",
          anchor: { x: 600, y: 0 },
          hosts: [{ id: "host-2", x: 0, y: 0 }],
        },
      ],
      attachments: [
        {
          id: "vulnerability-1",
          kind: "Vulnerability",
          anchorNodeIds: ["host-1"],
        },
        { id: "credential-1", kind: "Credential", anchorNodeIds: ["host-1"] },
        {
          id: "capability-1",
          kind: "MissionCapability",
          anchorNodeIds: ["host-1", "host-2"],
        },
      ],
    });

    const layout = arrangeTopology(scene);
    const frames = [...layout.frames.values()].map(frameRect);
    const contextRects = scene.attachments.map((attachment) =>
      rectOf(layout.positions.get(attachment.id)!, CONTEXT_SIZE),
    );

    for (const context of contextRects) {
      for (const frame of frames) {
        const gap = gaps(context, frame);
        expect(Math.max(gap.x, gap.y)).toBeGreaterThanOrEqual(
          CONTEXT_GAP - 1e-9,
        );
      }
    }

    for (let a = 0; a < contextRects.length; a++) {
      for (let b = a + 1; b < contextRects.length; b++) {
        const gap = gaps(contextRects[a]!, contextRects[b]!);
        expect(Math.max(gap.x, gap.y)).toBeGreaterThanOrEqual(
          CONTEXT_GAP - 1e-9,
        );
      }
    }
  });

  it("sizes a frame from packed content only", () => {
    const scene = buildScene({
      segments: [
        {
          id: "segment-small",
          anchor: { x: 5000, y: -9000 },
          hosts: [{ id: "host-1", x: 5000, y: -9000 }],
        },
        {
          id: "segment-large",
          anchor: { x: 0, y: 0 },
          hosts: Array.from({ length: 6 }, (_value, index) => ({
            id: `host-large-${index}`,
            x: -2000,
            y: index * 700,
          })),
        },
      ],
    });

    const layout = arrangeTopology(scene);
    const small = layout.frames.get("segment-small")!;
    const large = layout.frames.get("segment-large")!;

    expect(small.size).toEqual(
      packSegment(scene.segments.find((item) => item.id === "segment-small")!)
        .size,
    );
    expect(large.size).toEqual(
      packSegment(scene.segments.find((item) => item.id === "segment-large")!)
        .size,
    );
    expect(small.size.width).toBeLessThan(large.size.width);
    expect(small.size.height).toBeLessThan(large.size.height);
  });
});

describe("arranged positions", () => {
  const arrangedScene: SceneSpec = {
    segments: [
      {
        id: "segment-1",
        anchor: { x: 40, y: 60 },
        hosts: [
          {
            id: "host-1",
            x: 90,
            y: 150,
            services: [{ id: "service-1", x: 90, y: 240 }],
          },
          { id: "host-2", x: 240, y: 150 },
        ],
      },
      {
        id: "segment-2",
        anchor: { x: 1200, y: 40 },
        hosts: Array.from({ length: 6 }, (_value, index) => ({
          id: `host-${index + 10}`,
          x: index * 17,
          y: 300 + index,
        })),
      },
    ],
    attachments: [
      { id: "credential-1", kind: "Credential", anchorNodeIds: ["host-1"] },
      {
        id: "capability-1",
        kind: "MissionCapability",
        anchorNodeIds: ["service-1", "host-12"],
      },
    ],
  };

  it("places segments among the persisted positions", () => {
    const scene = buildScene(arrangedScene);
    const layout = arrangeTopology(scene);

    for (const segment of scene.segments) {
      const frame = layout.frames.get(segment.id)!;
      expect(layout.positions.get(segment.id)).toEqual({
        x: frame.position.x + SEGMENT_PADDING,
        y: frame.position.y + SEGMENT_PADDING,
      });
    }
  });

  it("recreates arranged frames from the persisted positions", () => {
    const scene = buildScene(arrangedScene);
    const arranged = arrangeTopology(scene);

    persistPositions(scene, arranged.positions);

    const measured = measureTopology(scene);
    expect(serialized(measured)).toBe(serialized(arranged));
  });
});

describe("measureTopology with frozen context", () => {
  function contextScene(): TopologyScene {
    return buildScene({
      segments: [
        {
          id: "segment-1",
          anchor: { x: 40, y: 40 },
          hosts: [{ id: "host-1", x: 60, y: 140 }],
        },
      ],
      attachments: [
        { id: "credential-1", kind: "Credential", anchorNodeIds: ["host-1"] },
        {
          id: "capability-1",
          kind: "MissionCapability",
          anchorNodeIds: ["host-1"],
        },
      ],
    });
  }

  it("reuses a frozen context position and keeps the rest of the layout", () => {
    const scene = contextScene();
    const free = measureTopology(scene);
    const frozen = new Map([["credential-1", { x: -400, y: -300 }]]);

    const layout = measureTopology(scene, { freezeContextPositions: frozen });

    expect(layout.positions.get("credential-1")).toEqual({ x: -400, y: -300 });
    expect(layout.frames).toEqual(free.frames);
    expect(layout.positions.get("host-1")).toEqual(
      free.positions.get("host-1"),
    );
  });

  it("keeps other context clear of a frozen context rect", () => {
    const scene = contextScene();
    const free = measureTopology(scene);
    const claimed = free.positions.get("capability-1")!;
    const frozen = new Map([["credential-1", claimed]]);

    const layout = measureTopology(scene, { freezeContextPositions: frozen });
    const capability = layout.positions.get("capability-1")!;
    const gap = gaps(
      rectOf(capability, CONTEXT_SIZE),
      rectOf(claimed, CONTEXT_SIZE),
    );

    expect(layout.positions.get("credential-1")).toEqual(claimed);
    expect(Math.max(gap.x, gap.y)).toBeGreaterThanOrEqual(CONTEXT_GAP - 1e-9);
  });

  it("keeps a frozen position that sits inside a segment frame", () => {
    const scene = contextScene();
    const anchor = { x: 60, y: 140 };
    const layout = measureTopology(scene, {
      freezeContextPositions: new Map([["credential-1", anchor]]),
    });

    const frame = layout.frames.get("segment-1")!;
    expect(layout.positions.get("credential-1")).toEqual(anchor);
    expect(frame.position.x).toBeLessThanOrEqual(anchor.x);
    expect(frame.position.y).toBeLessThanOrEqual(anchor.y);
  });
});

describe("measureTopology", () => {
  it("preserves authored positions and grows frames around members", () => {
    const scene = buildScene({
      segments: [
        {
          id: "segment-1",
          anchor: { x: 100, y: 100 },
          hosts: [
            {
              id: "host-1",
              x: 400,
              y: 900,
              services: [{ id: "service-1", x: 400, y: 980 }],
            },
            { id: "host-2", x: 150, y: 200 },
          ],
        },
      ],
    });

    const layout = measureTopology(scene);

    expect(layout.positions.get("host-1")).toEqual({ x: 400, y: 900 });
    expect(layout.positions.get("host-2")).toEqual({ x: 150, y: 200 });
    expect(layout.positions.get("service-1")).toEqual({ x: 400, y: 980 });

    const frame = layout.frames.get("segment-1")!;
    expect(frame.position.x).toBeLessThanOrEqual(100 - SEGMENT_PADDING);
    expect(frame.position.y).toBeLessThanOrEqual(100 - SEGMENT_PADDING);
    expect(frame.position.x + frame.size.width).toBeGreaterThanOrEqual(
      400 + NODE_WIDTH + SEGMENT_PADDING,
    );
    expect(frame.position.y + frame.size.height).toBeGreaterThanOrEqual(
      980 + SERVICE_SIZE.height + SEGMENT_PADDING,
    );
  });

  it("reserves a header band that authored members never overlap", () => {
    const scene = buildScene({
      segments: [
        { id: "segment-memberless", anchor: { x: 200, y: 200 }, hosts: [] },
        {
          id: "segment-flush",
          anchor: { x: 600, y: 400 },
          hosts: [
            {
              id: "host-flush",
              x: 600,
              y: 400,
              services: [{ id: "service-flush", x: 600, y: 420 }],
            },
          ],
        },
        {
          id: "segment-above",
          anchor: { x: 1200, y: 900 },
          hosts: [{ id: "host-above", x: 1200, y: 300 }],
        },
      ],
    });

    const layout = measureTopology(scene);

    for (const segment of scene.segments) {
      const frame = layout.frames.get(segment.id)!;
      const contentTop =
        frame.position.y + SEGMENT_HEADER_HEIGHT + SEGMENT_PADDING;

      for (const host of segment.hosts) {
        expect(layout.positions.get(host.id)!.y).toBeGreaterThanOrEqual(
          contentTop,
        );
        for (const service of host.services) {
          expect(layout.positions.get(service.id)!.y).toBeGreaterThanOrEqual(
            contentTop,
          );
        }
      }
    }

    const memberless = scene.segments.find(
      (segment) => segment.id === "segment-memberless",
    )!;
    expect(layout.frames.get("segment-memberless")!.size).toEqual(
      packSegment(memberless).size,
    );
  });

  it("measures one segment frame with the same geometry", () => {
    const scene = buildScene(singleSegment);
    const segment = scene.segments[0]!;
    const positions = new Map<string, { x: number; y: number }>();

    expect(measureSegmentFrame(segment, positions)).toEqual(
      measureTopology(scene).frames.get(segment.id)!,
    );
    expect(positions.get("host-1")).toEqual({ x: 90, y: 150 });
  });

  it("anchors a memberless frame at its authored position", () => {
    const scene = buildScene({
      segments: [{ id: "segment-1", anchor: { x: 40, y: 40 }, hosts: [] }],
    });

    const layout = measureTopology(scene);
    const frame = layout.frames.get("segment-1")!;

    expect(frame.position).toEqual({
      x: 40 - SEGMENT_PADDING,
      y: 40 - SEGMENT_PADDING,
    });
    expect(frame.size).toEqual(packSegment(scene.segments[0]!).size);
  });

  it("is deterministic for the same scene", () => {
    const scene = buildScene(singleSegment);
    expect(serialized(measureTopology(scene))).toBe(
      serialized(measureTopology(scene)),
    );
  });

  it("places shared context between distant anchors", () => {
    const scene = buildScene({
      segments: [
        {
          id: "segment-1",
          anchor: { x: 0, y: 0 },
          hosts: [
            {
              id: "host-1",
              x: 40,
              y: 120,
              services: [{ id: "service-1", x: 40, y: 220 }],
            },
          ],
        },
        {
          id: "segment-2",
          anchor: { x: 4000, y: 0 },
          hosts: [
            {
              id: "host-2",
              x: 4040,
              y: 120,
              services: [{ id: "service-2", x: 4040, y: 220 }],
            },
          ],
        },
      ],
      attachments: [
        {
          id: "capability-1",
          kind: "MissionCapability",
          anchorNodeIds: ["service-1", "service-2"],
        },
      ],
    });

    const layout = measureTopology(scene);
    const position = layout.positions.get("capability-1")!;
    const first = layout.positions.get("service-1")!;
    const second = layout.positions.get("service-2")!;

    expect(position.x).toBeGreaterThan(first.x);
    expect(position.x).toBeLessThan(second.x + SERVICE_SIZE.width);
  });

  it("leaves unplaced entities and their context without positions", () => {
    const scene = buildScene({
      segments: [
        {
          id: "segment-1",
          anchor: { x: 0, y: 0 },
          hosts: [{ id: "host-1", x: 40, y: 120 }],
        },
      ],
      attachments: [
        {
          id: "credential-1",
          kind: "Credential",
          anchorNodeIds: ["host-orphan"],
        },
        {
          id: "vulnerability-1",
          kind: "Vulnerability",
          anchorNodeIds: ["host-1"],
        },
      ],
      unplacedHosts: [{ id: "host-orphan", x: 900, y: 900 }],
    });

    const layout = measureTopology(scene);

    expect(layout.positions.has("host-orphan")).toBe(false);
    expect(layout.positions.has("credential-1")).toBe(false);
    expect(layout.positions.has("vulnerability-1")).toBe(true);
  });

  it("leaves a service whose owner host is unplaced without a position", () => {
    const scene = buildScene({
      segments: [
        {
          id: "segment-1",
          anchor: { x: 0, y: 0 },
          hosts: [{ id: "host-1", x: 40, y: 120 }],
        },
      ],
      unplacedHosts: [
        {
          id: "host-orphan",
          x: 900,
          y: 900,
          services: [{ id: "service-orphan", x: 900, y: 960 }],
        },
      ],
    });

    expect(scene.segments[0]!.hosts[0]!.services).toEqual([]);
    expect(
      scene.unplaced.map((entry) => [entry.entityId, entry.status]),
    ).toEqual([
      ["host-orphan", "placement_issue"],
      ["service-orphan", "no_placement"],
    ]);

    const layout = measureTopology(scene);

    expect(layout.positions.has("host-orphan")).toBe(false);
    expect(layout.positions.has("service-orphan")).toBe(false);
    expect(layout.positions.has("host-1")).toBe(true);
  });
});
