import type {
  Edge,
  GraphContract,
  Node,
} from "../../../contracts.generated/graph";
import type { TopologyProjection } from "../../../contracts.generated/dashboard/graph";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import {
  anchorRecord,
  attachmentRecord,
  containsEdge,
  credentialNode,
  flowGroupRecord,
  hostNode,
  hostRecord,
  policyGroupRecord,
  projectionOf,
  reachabilityEdge,
  runsEdge,
  segmentNode,
  segmentRecord,
  serviceNode,
  serviceRecord,
  storesCredentialEdge,
} from "../__tests__/topology-fixtures";
import TopologyCanvas from "./TopologyCanvas.svelte";
import type { Point } from "../canvas/canvasState";

interface Fixture {
  graph: GraphContract;
  projection: TopologyProjection;
}

const FAR_ZOOM_CLICKS = 5;
const NEAR_ZOOM_CLICKS = 10;

function fixture(): Fixture {
  const nodes: Node[] = [
    segmentNode("segment-a", 40, 40),
    segmentNode("segment-b", 700, 40),
    hostNode("host-a1", 60, 140),
    hostNode("host-a2", 220, 140),
    hostNode("host-a3", 380, 140),
    hostNode("host-b1", 720, 140),
    serviceNode("service-a1", 60, 240),
    credentialNode("credential-1", 60, 420),
  ];
  setSegmentData(nodes, "segment-a", "Zone A", "10.10.0.0/24");
  setSegmentData(nodes, "segment-b", "Zone B", null);

  const edges: Edge[] = [
    containsEdge("contains-a1", "segment-a", "host-a1"),
    containsEdge("contains-a2", "segment-a", "host-a2"),
    containsEdge("contains-a3", "segment-a", "host-a3"),
    containsEdge("contains-b1", "segment-b", "host-b1"),
    runsEdge("runs-a1", "host-a1", "service-a1"),
    storesCredentialEdge("stores-credential-1", "host-a1", "credential-1"),
    reachabilityEdge("policy-ab", "segment-a", "segment-b"),
  ];

  const projection = projectionOf({
    segments: [
      segmentRecord("segment-a", ["host-a1", "host-a2", "host-a3"], {
        service_count: 1,
        context_count: 1,
      }),
      segmentRecord("segment-b", ["host-b1"]),
    ],
    hosts: [
      hostRecord("host-a1", "segment-a", ["service-a1"], 1),
      hostRecord("host-a2", "segment-a"),
      hostRecord("host-a3", "segment-a"),
      hostRecord("host-b1", "segment-b"),
    ],
    services: [serviceRecord("service-a1", "host-a1")],
    attachments: [
      attachmentRecord("credential-1", "Credential", [
        anchorRecord("host-a1", "stores-credential-1", "StoresCredential"),
      ]),
    ],
    policy_groups: [policyGroupRecord("segment-a", "segment-b", ["policy-ab"])],
    flow_groups: [
      flowGroupRecord("host-a1", "host-b1", ["service-a1"], ["flow-ab"]),
    ],
  });

  return { graph: graphContract(nodes, edges), projection };
}

function graphContract(nodes: Node[], edges: Edge[]): GraphContract {
  return {
    id: "graph-1",
    title: "Topology",
    revision_id: "revision-1",
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    nodes,
    edges,
  };
}

function setSegmentData(
  nodes: Node[],
  id: string,
  name: string,
  cidr: string | null,
): void {
  const node = nodes.find((entry) => entry.id === id);
  if (node?.type === "NetworkSegment") node.data = { name, cidr };
}

function prepare(): {
  graph: GraphContract;
  projection: TopologyProjection;
} {
  return fixture();
}

function zoom(clicks: number): Promise<void> {
  return clicks > 0
    ? clickZoom("Zoom out", clicks)
    : clickZoom("Zoom in", -clicks);
}

async function clickZoom(name: string, clicks: number): Promise<void> {
  const button = screen.getByRole("button", { name });
  for (let index = 0; index < clicks; index++) await fireEvent.click(button);
}

function assignPointerCapture(element: Element): void {
  Object.assign(element, {
    setPointerCapture: () => {},
    hasPointerCapture: () => true,
    releasePointerCapture: () => {},
  });
}

function translateOf(element: Element | null): Point | null {
  const match = /translate\(([-\d.]+)[\s,]+([-\d.]+)\)/.exec(
    element?.getAttribute("transform") ?? "",
  );
  return match ? { x: Number(match[1]), y: Number(match[2]) } : null;
}

/** Host position at any detail level. Near detail nests the typed card. */
function hostPosition(container: HTMLElement, id: string): Point | null {
  const wrapper = container.querySelector(`[data-node-id='${id}']`);
  if (!wrapper) return null;
  return (
    translateOf(wrapper) ??
    translateOf(wrapper.querySelector(".canvas-node")) ??
    null
  );
}

function worldRect(element: Element): {
  x: number;
  y: number;
  width: number;
  height: number;
} {
  const position = elementPosition(element);
  const rect = element.querySelector("rect");
  return {
    x: position.x,
    y: position.y,
    width: Number(rect?.getAttribute("width") ?? 0),
    height: Number(rect?.getAttribute("height") ?? 0),
  };
}

/** Near detail nests the typed card, which carries the translation. */
function elementPosition(element: Element): Point {
  return (
    translateOf(element) ??
    translateOf(element.querySelector(".canvas-node")) ?? { x: 0, y: 0 }
  );
}

function overlaps(
  a: { x: number; y: number; width: number; height: number },
  b: { x: number; y: number; width: number; height: number },
): boolean {
  return (
    a.x < b.x + b.width &&
    b.x < a.x + a.width &&
    a.y < b.y + b.height &&
    b.y < a.y + a.height
  );
}

/** Waits for queued animation frames, which jsdom schedules as timers. */
async function nextFrame(): Promise<void> {
  await new Promise<void>((resolve) =>
    requestAnimationFrame(() => resolve(undefined)),
  );
  await new Promise<void>((resolve) =>
    requestAnimationFrame(() => resolve(undefined)),
  );
}

/** Waits for pending rerenders and microtasks. */
function flushAsync(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

/** Places a world rectangle on screen with the rendered world transform. */
function screenRect(
  container: HTMLElement,
  element: Element,
): { x: number; y: number; width: number; height: number } {
  const transform = container
    .querySelector(".topology-world")!
    .getAttribute("transform")!;
  const match =
    /translate\(([-\d.]+)[\s,]+([-\d.]+)\)\s+scale\(([-\d.]+)\)/.exec(
      transform,
    )!;
  const pan = { x: Number(match[1]), y: Number(match[2]) };
  const scale = Number(match[3]);
  const world = worldRect(element);
  return {
    x: world.x * scale + pan.x,
    y: world.y * scale + pan.y,
    width: world.width * scale,
    height: world.height * scale,
  };
}

/** Sorted ids of the entities the canvas currently draws. */
function revealedNodeIds(container: HTMLElement): string[] {
  return [...container.querySelectorAll("[data-node-id]")]
    .map((element) => element.getAttribute("data-node-id")!)
    .sort();
}

describe("TopologyCanvas", () => {
  beforeEach(() => {
    Object.defineProperty(window.Element.prototype, "clientWidth", {
      configurable: true,
      value: 1200,
    });
    Object.defineProperty(window.Element.prototype, "clientHeight", {
      configurable: true,
      value: 800,
    });
  });
  afterEach(cleanup);

  it("renders one canvas with segments, members, and attached context", () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, selectedNodeId: "host-a1" },
    });

    expect(container.querySelectorAll("svg.topology-graph")).toHaveLength(1);
    expect(container.querySelectorAll("[data-segment-id]")).toHaveLength(2);
    expect(container.querySelector("[data-node-id='host-a1']")).not.toBeNull();
    expect(
      container.querySelector("[data-node-id='credential-1']"),
    ).not.toBeNull();
  });

  it("keeps attached context outside every segment frame", () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, selectedNodeId: "host-a1" },
    });

    const context = worldRect(
      container.querySelector("[data-node-id='credential-1']")!,
    );
    for (const segment of container.querySelectorAll("[data-segment-id]")) {
      expect(overlaps(context, worldRect(segment))).toBe(false);
    }
  });

  it("keeps hosts and services inside their segment frame", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection },
    });

    await zoom(-NEAR_ZOOM_CLICKS);

    const frame = worldRect(
      container.querySelector("[data-segment-id='segment-a']")!,
    );
    for (const id of ["host-a1", "host-a2", "host-a3", "service-a1"]) {
      const member = worldRect(
        container.querySelector(`[data-node-id='${id}']`)!,
      );
      expect(member.x).toBeGreaterThanOrEqual(frame.x);
      expect(member.y).toBeGreaterThanOrEqual(frame.y);
      expect(member.x + member.width).toBeLessThanOrEqual(
        frame.x + frame.width,
      );
      expect(member.y + member.height).toBeLessThanOrEqual(
        frame.y + frame.height,
      );
    }
  });

  it("renders a grouped segment-pair bundle instead of raw edges", () => {
    const { graph, projection } = prepare();
    const withoutGroups = projectionOf({
      segments: projection.segments,
      hosts: projection.hosts,
      services: projection.services,
      attachments: projection.attachments,
      flow_groups: projection.flow_groups,
    });
    const { container } = render(TopologyCanvas, {
      props: { graph, projection: withoutGroups },
    });

    expect(container.querySelector("[data-policy-from]")).toBeNull();
    expect(container.querySelector(".topology-flow")).toBeNull();
    expect(
      container.querySelector("[data-bundle-key='segment-a:segment-b']"),
    ).not.toBeNull();
  });

  it("summarizes at far detail and reveals editable detail near", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });
    const frameBefore = container
      .querySelector("[data-segment-id='segment-a']")!
      .getAttribute("transform");
    const hostBefore = hostPosition(container, "host-a1");

    await zoom(FAR_ZOOM_CLICKS);

    expect(container.querySelector("[data-node-id='host-a1']")).toBeNull();
    expect(container.textContent).toContain("3 hosts");
    expect(container.textContent).toContain("1 context item");
    expect(
      container
        .querySelector("[data-segment-id='segment-a']")!
        .getAttribute("transform"),
    ).toBe(frameBefore);

    await zoom(-NEAR_ZOOM_CLICKS);

    expect(
      container.querySelector("[data-node-id='service-a1']"),
    ).not.toBeNull();
    expect(
      container.querySelectorAll(".topology-structural-edge"),
    ).toHaveLength(1);
    expect(hostPosition(container, "host-a1")).toEqual(hostBefore);
    expect(
      container
        .querySelector("[data-segment-id='segment-a']")!
        .getAttribute("transform"),
    ).toBe(frameBefore);
  });

  it("keeps far detail until the zoom leaves the threshold band", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });

    await zoom(FAR_ZOOM_CLICKS);
    expect(container.querySelector("[data-node-id='host-a1']")).toBeNull();

    await zoom(-2);
    expect(container.querySelector("[data-node-id='host-a1']")).toBeNull();

    await zoom(-1);
    expect(container.querySelector("[data-node-id='host-a1']")).not.toBeNull();
  });

  it("summarizes relationships into one directed bundle per segment pair at far detail", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });

    await zoom(FAR_ZOOM_CLICKS);

    expect(container.querySelector(".topology-policy")).toBeNull();
    expect(container.querySelector(".topology-flow")).toBeNull();
    expect(container.querySelectorAll("[data-bundle-key]")).toHaveLength(1);

    const bundle = container.querySelector(
      "[data-bundle-key='segment-a:segment-b']",
    )!;
    expect(bundle.getAttribute("data-bundle-connections")).toBe("2");
    expect(bundle.getAttribute("aria-label")).toBe(
      "Zone A to Zone B, 2 connections, service-a1 · host-a1 → host-b1",
    );
    expect(
      container.querySelector("[data-bundle-visual='segment-a:segment-b']")
        ?.textContent,
    ).toContain("2");
    expect(bundle.getAttribute("aria-expanded")).toBe("false");
  });

  it("keeps segment-pair bundles and hides detailed lines at every zoom", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });

    for (const zoomChange of [0, FAR_ZOOM_CLICKS, -NEAR_ZOOM_CLICKS]) {
      if (zoomChange !== 0) await zoom(zoomChange);
      expect(container.querySelector(".topology-policy")).toBeNull();
      expect(container.querySelector(".topology-flow")).toBeNull();
      expect(container.querySelectorAll("[data-bundle-key]")).toHaveLength(1);
    }
  });

  it("opens one bundle popover on hover, keyboard focus, and click", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });
    await zoom(FAR_ZOOM_CLICKS);
    const bundle = container.querySelector(
      "[data-bundle-key='segment-a:segment-b']",
    )!;

    await fireEvent.pointerEnter(bundle);
    expect(screen.getByRole("tooltip")).toHaveTextContent("Zone A → Zone B");
    expect(screen.getByRole("tooltip")).toHaveTextContent(
      "service-a1 · host-a1 → host-b1",
    );

    await fireEvent.pointerLeave(bundle);
    expect(screen.queryByRole("tooltip")).not.toBeInTheDocument();

    await fireEvent.focus(bundle);
    expect(screen.getByRole("tooltip")).toBeInTheDocument();

    await fireEvent.blur(bundle);
    expect(screen.queryByRole("tooltip")).not.toBeInTheDocument();

    await fireEvent.click(bundle);
    expect(bundle.getAttribute("aria-expanded")).toBe("true");
    expect(screen.getByRole("tooltip")).toHaveTextContent(
      "service-a1 · host-a1 → host-b1",
    );

    await fireEvent.keyDown(container.querySelector(".topology-surface")!, {
      key: "Escape",
    });
    expect(screen.queryByRole("tooltip")).not.toBeInTheDocument();
    expect(bundle.getAttribute("aria-expanded")).toBe("false");
  });

  it("layers bundle hit areas over frames but below headers and members", async () => {
    const { graph, projection } = prepare();
    const onSelectEdge = vi.fn();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        onSelectEdge,
        onSelectNode: vi.fn(),
      },
    });
    const bundle = container.querySelector(
      "[data-bundle-key='segment-a:segment-b']",
    )!;
    const hit = bundle.querySelector(".topology-bundle-hit")!;
    const frame = container.querySelector(
      "[data-segment-id='segment-a'] .topology-segment-frame",
    )!;
    const header = container.querySelector(
      "[data-segment-header='segment-a']",
    )!;
    const host = container.querySelector("[data-node-id='host-a1']")!;

    // The visual path cannot own the pointer. The transparent stroke explicitly
    // does, so exposed portions of the line retain hover and click behavior.
    expect(getComputedStyle(hit).pointerEvents).toBe("stroke");
    expect(
      frame.compareDocumentPosition(bundle) &
        globalThis.Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(
      bundle.compareDocumentPosition(header) &
        globalThis.Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(
      bundle.compareDocumentPosition(host) &
        globalThis.Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();

    await fireEvent.pointerEnter(bundle);
    expect(screen.getByRole("tooltip")).toBeInTheDocument();
    await fireEvent.click(hit);
    expect(onSelectEdge).toHaveBeenCalledWith("policy-ab");
  });

  it("clamps a bundle popover to a narrow viewport", async () => {
    Object.defineProperty(window.Element.prototype, "clientWidth", {
      configurable: true,
      value: 390,
    });
    Object.defineProperty(window.Element.prototype, "clientHeight", {
      configurable: true,
      value: 180,
    });
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });

    await fireEvent.click(
      container.querySelector("[data-bundle-key='segment-a:segment-b']")!,
    );

    const popover = screen.getByRole("tooltip");
    expect(Number.parseFloat(popover.style.left)).toBeGreaterThanOrEqual(8);
    expect(Number.parseFloat(popover.style.left)).toBeLessThanOrEqual(126);
    expect(Number.parseFloat(popover.style.top)).toBe(8);
  });

  it("shows only selected host outgoing details and closes them correctly", async () => {
    const { graph, projection } = prepare();
    const withIncoming = projectionOf({
      ...projection,
      flow_groups: [
        ...projection.flow_groups,
        flowGroupRecord("host-b1", "host-a1", ["service-a1"], ["flow-ba"]),
      ],
    });
    const { container, rerender } = render(TopologyCanvas, {
      props: {
        graph,
        projection: withIncoming,
        autoFit: false,
        selectedNodeId: "host-a1",
      },
    });

    const panel = () => container.querySelector("[data-host-connections]");
    expect(panel()).toHaveAttribute("data-host-connections", "host-a1");
    expect(panel()).toHaveTextContent("service-a1 · host-a1 → host-b1");
    expect(panel()).not.toHaveTextContent("host-b1 → host-a1");

    await rerender({
      graph,
      projection: withIncoming,
      autoFit: false,
      selectedNodeId: "host-b1",
    });
    expect(panel()).toHaveAttribute("data-host-connections", "host-b1");
    expect(panel()).toHaveTextContent("service-a1 · host-b1 → host-a1");

    await rerender({
      graph,
      projection: withIncoming,
      autoFit: false,
      selectedNodeId: "segment-a",
    });
    expect(panel()).toBeNull();

    await rerender({
      graph,
      projection: withIncoming,
      autoFit: false,
      selectedNodeId: undefined,
    });
    expect(panel()).toBeNull();

    await rerender({
      graph,
      projection: withIncoming,
      autoFit: false,
      selectedNodeId: "host-a1",
    });
    expect(panel()).not.toBeNull();
    await fireEvent.keyDown(container.querySelector(".topology-surface")!, {
      key: "Escape",
    });
    expect(panel()).toBeNull();
  });

  it("shows an empty selected-host outgoing detail", () => {
    const { graph, projection } = prepare();
    const withoutFlows = projectionOf({ ...projection, flow_groups: [] });
    render(TopologyCanvas, {
      props: {
        graph,
        projection: withoutFlows,
        autoFit: false,
        selectedNodeId: "host-a1",
      },
    });

    expect(screen.getByText("No outgoing connections")).toBeInTheDocument();
  });

  it("lists no service in a bundle without a flow", async () => {
    const { graph, projection } = prepare();
    const policyOnly = projectionOf({
      segments: projection.segments,
      hosts: projection.hosts,
      services: projection.services,
      attachments: projection.attachments,
      policy_groups: projection.policy_groups,
    });
    const { container } = render(TopologyCanvas, {
      props: { graph, projection: policyOnly, autoFit: false },
    });

    await zoom(FAR_ZOOM_CLICKS);
    const bundle = container.querySelector(
      "[data-bundle-key='segment-a:segment-b']",
    )!;
    expect(bundle.getAttribute("data-bundle-connections")).toBe("1");
    expect(bundle.getAttribute("aria-label")).toBe(
      "Zone A to Zone B, 1 connection, no services",
    );

    await fireEvent.click(bundle);

    expect(screen.getByRole("tooltip")).toHaveTextContent("No services");
  });

  it("draws no bundle loop line for self-segment policy", async () => {
    const { graph, projection } = prepare();
    const selfPolicy = projectionOf({
      ...projection,
      policy_groups: [
        ...projection.policy_groups,
        policyGroupRecord("segment-a", "segment-a", ["policy-aa"]),
      ],
    });
    const { container } = render(TopologyCanvas, {
      props: { graph, projection: selfPolicy, autoFit: false },
    });

    await zoom(FAR_ZOOM_CLICKS);

    expect(
      container.querySelector("[data-bundle-key='segment-a:segment-a']"),
    ).toBeNull();
    expect(container.querySelector(".topology-self-policy")).not.toBeNull();
  });

  it("shows a distinct pending cue and keeps editing state", () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        projectionStatus: "pending",
        pendingEntityIds: ["host-a1"],
      },
    });

    expect(screen.getByText("Updating topology")).toBeInTheDocument();
    expect(
      container
        .querySelector("[data-node-id='host-a1']")!
        .getAttribute("data-projection-cue"),
    ).toBe("pending");
  });

  it("keeps the last accepted scene and marks it stale on a projection error", () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, projectionStatus: "error" },
    });

    expect(
      container.querySelector(".topology-surface")!.getAttribute("data-stale"),
    ).toBe("true");
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Topology grouping is unavailable. Graph editing remains available.",
    );
    expect(
      container.querySelector("[data-segment-id='segment-a']"),
    ).not.toBeNull();
    expect(container.querySelector("[data-node-id='host-a1']")).not.toBeNull();
  });

  it("cues a placement issue apart from a pending change", () => {
    const { graph, projection } = prepare();
    const orphan = hostNode("host-orphan", 900, 400);
    const { container } = render(TopologyCanvas, {
      props: {
        graph: graphContract([...graph.nodes, orphan], graph.edges),
        projection: projectionOf({
          ...projection,
          issues: [
            {
              code: "host_without_segment",
              severity: "warning",
              entity_id: "host-orphan",
              related_ids: [],
            },
          ],
        }),
      },
    });

    const floater = container.querySelector("[data-node-id='host-orphan']");
    expect(floater).not.toBeNull();
    expect(floater!.getAttribute("data-projection-cue")).toBe(
      "placement-issue",
    );
    expect(floater!.getAttribute("data-unplaced-status")).toBe(
      "placement_issue",
    );
    expect(screen.getByText("1 placement issue")).toBeInTheDocument();
  });

  it("labels draft operational flows as unsaved", () => {
    const { graph, projection } = prepare();
    render(TopologyCanvas, {
      props: { graph, projection, projectionSource: "draft" },
    });

    expect(
      screen.getByText("Draft reachability · Save before simulation"),
    ).toBeInTheDocument();
  });

  it("drags a segment with its members and leaves attached context alone", async () => {
    const { graph, projection } = prepare();
    const onGeometryChange = vi.fn();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, onGeometryChange, autoFit: false },
    });
    const surface = container.querySelector(".topology-surface")!;
    const header = container.querySelector(
      "[data-segment-header='segment-a']",
    )!;
    assignPointerCapture(surface);
    assignPointerCapture(header);

    await fireEvent.pointerDown(header, {
      button: 0,
      isPrimary: true,
      pointerId: 1,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 1,
      clientX: 40,
      clientY: 20,
    });

    // Geometry coalesces into animation frames, so the release commits it.
    expect(onGeometryChange).not.toHaveBeenCalled();

    await fireEvent.pointerUp(surface, { pointerId: 1 });

    const positions = onGeometryChange.mock.calls.at(-1)?.[0] as Map<
      string,
      Point
    >;
    expect([...positions.keys()].sort()).toEqual([
      "host-a1",
      "host-a2",
      "host-a3",
      "segment-a",
      "service-a1",
    ]);
    expect(positions.get("segment-a")).toEqual({ x: 80, y: 60 });
    expect(positions.get("host-a1")).toEqual({ x: 100, y: 160 });
    expect(positions.has("credential-1")).toBe(false);

    expect(onGeometryChange).toHaveBeenCalledTimes(1);
    expect(graph.edges).toHaveLength(7);
    expect(
      graph.nodes.find((node) => node.id === "credential-1")!.view_data,
    ).toEqual({ x_pos: 60, y_pos: 420 });
  });

  it("drags an entity as geometry only", async () => {
    const { graph, projection } = prepare();
    const onGeometryChange = vi.fn();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        onGeometryChange,
        autoFit: false,
        // Attached context is baseline-hidden, so pin it to keep it drawn.
        pinnedEntityIds: ["credential-1"],
      },
    });
    const surface = container.querySelector(".topology-surface")!;
    const host = container.querySelector("[data-node-id='host-a1']")!;
    assignPointerCapture(surface);
    assignPointerCapture(host);

    await fireEvent.pointerDown(host, {
      button: 0,
      isPrimary: true,
      pointerId: 2,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 2,
      clientX: 30,
      clientY: 10,
    });
    await fireEvent.pointerUp(surface, { pointerId: 2 });

    const positions = onGeometryChange.mock.calls.at(-1)?.[0] as Map<
      string,
      Point
    >;
    expect([...positions.keys()]).toEqual(["host-a1"]);
    expect(positions.get("host-a1")).toEqual({ x: 90, y: 150 });
    expect(graph.edges).toHaveLength(7);

    const context = container.querySelector("[data-node-id='credential-1']")!;
    assignPointerCapture(context);
    await fireEvent.pointerDown(context, {
      button: 0,
      isPrimary: true,
      pointerId: 3,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 3,
      clientX: 50,
      clientY: 50,
    });

    expect(onGeometryChange).toHaveBeenCalledTimes(1);
  });

  it("exposes a read-only canvas without drag affordances", async () => {
    const { graph, projection } = prepare();
    const onGeometryChange = vi.fn();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        readOnly: true,
        onGeometryChange,
        autoFit: false,
      },
    });
    const surface = container.querySelector(".topology-surface")!;
    const header = container.querySelector(
      "[data-segment-header='segment-a']",
    )!;
    assignPointerCapture(surface);
    assignPointerCapture(header);

    await fireEvent.pointerDown(header, {
      button: 0,
      isPrimary: true,
      pointerId: 4,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 4,
      clientX: 40,
      clientY: 20,
    });

    expect(onGeometryChange).not.toHaveBeenCalled();
    expect(container.querySelector(".canvas-node-connector")).toBeNull();
  });

  it("fits the scene when the view command changes", async () => {
    const { graph, projection } = prepare();
    const { container, rerender } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });
    const world = container.querySelector(".topology-world")!;
    const before = world.getAttribute("transform");

    await rerender({
      graph,
      projection,
      autoFit: false,
      viewCommand: { kind: "fit", token: 1 },
    });

    expect(world.getAttribute("transform")).not.toBe(before);
  });

  it("focuses an entity without moving its world position", async () => {
    const { graph, projection } = prepare();
    const { container, rerender } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });
    const world = container.querySelector(".topology-world")!;
    const hostBefore = hostPosition(container, "host-b1");

    await rerender({
      graph,
      projection,
      autoFit: false,
      viewCommand: { kind: "focus", entityId: "host-b1", token: 1 },
    });

    expect(world.getAttribute("transform")).toMatch(/scale\(1\.5\)/);
    expect(hostPosition(container, "host-b1")).toEqual(hostBefore);
  });

  it("resets the viewport to the initial zoom and origin", async () => {
    const { graph, projection } = prepare();
    const { container, rerender } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });
    await clickZoom("Zoom out", 2);
    const world = container.querySelector(".topology-world")!;
    const before = world.getAttribute("transform");

    await rerender({
      graph,
      projection,
      autoFit: false,
      viewCommand: { kind: "reset", token: 1 },
    });

    expect(world.getAttribute("transform")).not.toBe(before);
    expect(world.getAttribute("transform")).toMatch(/scale\(1\)/);
  });

  it("passes appearance hooks to nodes and bundles", () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        nodeAppearance: () => ({ cardOpacity: 0.4 }),
        bundleAppearance: () => ({ strokeWidth: 7 }),
      },
    });

    expect(
      container
        .querySelector("[data-node-id='host-a1']")!
        .getAttribute("style"),
    ).toMatch(/--node-card-opacity:\s*0\.4/);
    expect(
      container.querySelector(".topology-bundle")!.getAttribute("style"),
    ).toMatch(/--bundle-stroke-width:\s*7/);
  });

  it("coalesces a drag into one geometry update per animation frame", async () => {
    const { graph, projection } = prepare();
    const onGeometryChange = vi.fn();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, onGeometryChange, autoFit: false },
    });
    const surface = container.querySelector(".topology-surface")!;
    const host = container.querySelector("[data-node-id='host-a1']")!;
    assignPointerCapture(surface);
    assignPointerCapture(host);

    await fireEvent.pointerDown(host, {
      button: 0,
      isPrimary: true,
      pointerId: 21,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 21,
      clientX: 10,
      clientY: 5,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 21,
      clientX: 20,
      clientY: 10,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 21,
      clientX: 30,
      clientY: 15,
    });

    expect(onGeometryChange).not.toHaveBeenCalled();

    await nextFrame();

    expect(onGeometryChange).toHaveBeenCalledTimes(1);
    expect(onGeometryChange.mock.calls.at(-1)?.[0].get("host-a1")).toEqual({
      x: 90,
      y: 155,
    });

    await fireEvent.pointerMove(surface, {
      pointerId: 21,
      clientX: 40,
      clientY: 20,
    });
    await fireEvent.pointerUp(surface, { pointerId: 21 });

    expect(onGeometryChange).toHaveBeenCalledTimes(2);
    expect(onGeometryChange.mock.calls.at(-1)?.[0].get("host-a1")).toEqual({
      x: 100,
      y: 160,
    });
  });

  it("keeps attached context in place while members drag", async () => {
    const { graph, projection } = prepare();
    let current = graph;
    const handler = (positions: ReadonlyMap<string, Point>) => {
      // The document persists drag geometry, so the canvas renders the next
      // graph revision. This mirrors the editor compositor.
      current = {
        ...current,
        nodes: current.nodes.map((node) => {
          const next = positions.get(node.id);
          return next
            ? {
                ...node,
                view_data: { ...node.view_data, x_pos: next.x, y_pos: next.y },
              }
            : node;
        }),
      };
      void rerender({
        graph: current,
        projection,
        autoFit: false,
        pinnedEntityIds: ["credential-1"],
        onGeometryChange: handler,
      });
    };
    const { container, rerender } = render(TopologyCanvas, {
      props: {
        graph: current,
        projection,
        autoFit: false,
        pinnedEntityIds: ["credential-1"],
        onGeometryChange: handler,
      },
    });

    const context = () =>
      translateOf(container.querySelector("[data-node-id='credential-1']"));
    const frame = () =>
      translateOf(container.querySelector("[data-segment-id='segment-a']"));
    const contextBefore = context();
    const frameBefore = frame();
    const surface = container.querySelector(".topology-surface")!;
    const header = container.querySelector(
      "[data-segment-header='segment-a']",
    )!;
    assignPointerCapture(surface);
    assignPointerCapture(header);

    await fireEvent.pointerDown(header, {
      button: 0,
      isPrimary: true,
      pointerId: 31,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 31,
      clientX: 40,
      clientY: 20,
    });
    await fireEvent.pointerUp(surface, { pointerId: 31 });
    await flushAsync();

    expect(contextBefore).not.toBeNull();
    expect(frame()).not.toEqual(frameBefore);
    expect(context()).toEqual(contextBefore);

    const host = container.querySelector("[data-node-id='host-a1']")!;
    const hostBefore = hostPosition(container, "host-a1");
    assignPointerCapture(host);

    await fireEvent.pointerDown(host, {
      button: 0,
      isPrimary: true,
      pointerId: 32,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 32,
      clientX: 10,
      clientY: 10,
    });
    await fireEvent.pointerUp(surface, { pointerId: 32 });
    await flushAsync();

    expect(hostPosition(container, "host-a1")).not.toEqual(hostBefore);
    expect(context()).toEqual(contextBefore);
  });

  it("labels an unplaced entity with its name and typed reason", () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: {
        graph: graphContract(
          [
            ...graph.nodes,
            hostNode("host-orphan", 900, 400),
            serviceNode("service-orphan", 900, 500),
            hostNode("host-pending", 900, 600),
          ],
          graph.edges,
        ),
        projection: projectionOf({
          ...projection,
          services: [
            ...projection.services,
            serviceRecord("service-orphan", null),
          ],
          issues: [
            {
              code: "host_without_segment",
              severity: "warning",
              entity_id: "host-orphan",
              related_ids: [],
            },
          ],
        }),
        pendingEntityIds: ["host-pending"],
        autoFit: false,
      },
    });

    const orphan = container.querySelector("[data-node-id='host-orphan']")!;
    expect(orphan.getAttribute("data-unplaced-reason")).toBe(
      "host_without_segment",
    );
    expect(orphan.getAttribute("aria-label")).toBe(
      "Host host-orphan, no segment",
    );
    expect(orphan.textContent).toContain("host-orphan");
    expect(orphan.textContent).toContain("no segment");

    const orphanService = container.querySelector(
      "[data-node-id='service-orphan']",
    )!;
    expect(orphanService.getAttribute("data-unplaced-reason")).toBe(
      "no_placement",
    );
    expect(orphanService.getAttribute("aria-label")).toBe(
      "Service service-orphan, no host",
    );

    const pending = container.querySelector("[data-node-id='host-pending']")!;
    expect(pending.getAttribute("data-unplaced-reason")).toBe("pending");
    expect(pending.getAttribute("aria-label")).toBe(
      "Host host-pending, awaiting topology update",
    );
  });

  it("renders structural connectors only where projection membership agrees", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: {
        graph: graphContract(graph.nodes, [
          ...graph.edges,
          containsEdge("contains-stray", "segment-b", "host-a1"),
          runsEdge("runs-stray", "host-a2", "service-a1"),
        ]),
        projection,
        autoFit: false,
      },
    });

    await zoom(-NEAR_ZOOM_CLICKS);

    expect(
      container.querySelectorAll(".topology-structural-edge"),
    ).toHaveLength(1);
    expect(
      container.querySelector("[data-edge-id='contains-stray']"),
    ).toBeNull();
    expect(container.querySelector("[data-edge-id='runs-stray']")).toBeNull();
    expect(container.querySelector("[data-edge-id='runs-a1']")).not.toBeNull();
  });

  it("never draws an authored Contains connector", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false, onSelectEdge: vi.fn() },
    });

    await zoom(-NEAR_ZOOM_CLICKS);

    for (const edge of graph.edges) {
      if (edge.type !== "Contains") continue;
      expect(container.querySelector(`[data-edge-id='${edge.id}']`)).toBeNull();
    }
  });

  it("does not let a finished drag swallow the next selection", async () => {
    const { graph, projection } = prepare();
    const onSelectNode = vi.fn();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        onGeometryChange: vi.fn(),
        onSelectNode,
      },
    });
    const surface = container.querySelector(".topology-surface")!;
    const header = container.querySelector(
      "[data-segment-header='segment-a']",
    )!;
    assignPointerCapture(surface);
    assignPointerCapture(header);

    await fireEvent.pointerDown(header, {
      button: 0,
      isPrimary: true,
      pointerId: 41,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 41,
      clientX: 40,
      clientY: 20,
    });
    await fireEvent.pointerUp(surface, { pointerId: 41 });
    // The drag ends away from its own element: the surface click closes it.
    await fireEvent.click(surface);

    expect(onSelectNode).not.toHaveBeenCalled();

    await fireEvent.click(container.querySelector("[data-node-id='host-a1']")!);

    expect(onSelectNode).toHaveBeenCalledWith("host-a1");
  });

  it("fits a loaded graph once when the viewport becomes available", async () => {
    const { graph, projection } = prepare();
    const authored = graph.nodes.map((node) => ({ ...node.view_data }));
    const { container, rerender } = render(TopologyCanvas, {
      props: { graph, projection },
    });
    const world = container.querySelector(".topology-world")!;

    expect(world.getAttribute("transform")).not.toBe("translate(0 0) scale(1)");
    for (const segment of container.querySelectorAll("[data-segment-id]")) {
      const rect = screenRect(container, segment);
      expect(rect.x).toBeGreaterThanOrEqual(0);
      expect(rect.y).toBeGreaterThanOrEqual(0);
      expect(rect.x + rect.width).toBeLessThanOrEqual(1200);
      expect(rect.y + rect.height).toBeLessThanOrEqual(800);
    }
    // A fit moves the view only. It never changes graph geometry.
    expect(graph.nodes.map((node) => ({ ...node.view_data }))).toEqual(
      authored,
    );

    await clickZoom("Zoom out", 1);
    const userView = world.getAttribute("transform");

    await rerender({
      graph: graphContract(graph.nodes, graph.edges),
      projection,
    });

    expect(world.getAttribute("transform")).toBe(userView);
    expect(userView).not.toBe("translate(0 0) scale(1)");
  });

  it("waits for a viewport before it fits a loaded graph", () => {
    Object.defineProperty(window.Element.prototype, "clientWidth", {
      configurable: true,
      value: 0,
    });
    Object.defineProperty(window.Element.prototype, "clientHeight", {
      configurable: true,
      value: 0,
    });
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: { graph, projection },
    });

    expect(
      container.querySelector(".topology-world")!.getAttribute("transform"),
    ).toBe("translate(0 0) scale(1)");
  });

  it("never fits a graph the caller reports as unloaded", async () => {
    const { graph, projection } = prepare();
    const { container, rerender } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });
    const world = container.querySelector(".topology-world")!;

    expect(world.getAttribute("transform")).toBe("translate(0 0) scale(1)");

    // A later load flag must not move a graph the user already authors.
    await rerender({ graph, projection, autoFit: true });

    expect(world.getAttribute("transform")).toBe("translate(0 0) scale(1)");
  });

  it("offers no add actions in read-only mode", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        readOnly: true,
        autoFit: false,
        onAddNode: vi.fn(),
        onGeometryChange: vi.fn(),
      },
    });

    await fireEvent.contextMenu(container.querySelector(".topology-surface")!);

    expect(screen.queryByText("Add")).toBeNull();
    expect(screen.queryByText("Delete selection")).toBeNull();
  });

  it("offers add and delete actions when the canvas is editable", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        onAddNode: vi.fn(),
        onGeometryChange: vi.fn(),
        onDeleteSelection: vi.fn(),
      },
    });

    await fireEvent.contextMenu(container.querySelector(".topology-surface")!);

    expect(screen.getByText("Add")).toBeInTheDocument();
    expect(screen.getByText("Delete selection")).toBeInTheDocument();
  });

  it("reveals the selection neighborhood and dims unrelated content", async () => {
    const { graph, projection } = prepare();
    const { container, rerender } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });

    // The zoom baseline summarizes services and hides attached context.
    expect(container.querySelector("[data-node-id='service-a1']")).toBeNull();
    expect(container.querySelector("[data-node-id='credential-1']")).toBeNull();
    expect(container.querySelectorAll(".topology-anchor-link")).toHaveLength(0);
    expect(container.querySelector("[data-node-id='host-b1']")).not.toBeNull();
    const segmentBefore = container
      .querySelector("[data-segment-id='segment-b']")!
      .getAttribute("transform");

    await rerender({
      graph,
      projection,
      autoFit: false,
      selectedNodeId: "host-a1",
    });

    // The lens reveals the service, the attached context, and the anchor link
    // above the baseline.
    expect(
      container.querySelector("[data-node-id='service-a1']"),
    ).not.toBeNull();
    expect(
      container.querySelector("[data-node-id='credential-1']"),
    ).not.toBeNull();
    expect(container.querySelectorAll(".topology-anchor-link")).toHaveLength(1);
    // The other segment stays in place and dims.
    const otherSegment = container.querySelector(
      "[data-segment-id='segment-b']",
    )!;
    expect(otherSegment.getAttribute("transform")).toBe(segmentBefore);
    expect(otherSegment.classList.contains("is-dimmed")).toBe(true);
    expect(
      container.querySelector("[data-segment-id='segment-a']")!.classList,
    ).not.toContain("is-dimmed");
    expect(
      container.querySelector("[data-node-id='host-b1']")!.classList,
    ).toContain("is-dimmed");
  });

  it("reveals attached context only through the lens", async () => {
    const { graph, projection } = prepare();
    const { container, rerender } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false },
    });

    // Medium detail alone never shows attached context.
    expect(container.querySelector("[data-node-id='credential-1']")).toBeNull();

    await rerender({
      graph,
      projection,
      autoFit: false,
      pinnedEntityIds: ["credential-1"],
    });

    expect(
      container.querySelector("[data-node-id='credential-1']"),
    ).not.toBeNull();
  });

  it("reveals pinned attached context at far detail", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        pinnedEntityIds: ["credential-1"],
      },
    });

    await zoom(FAR_ZOOM_CLICKS);

    // Far detail hides hosts, but the pin keeps the context and its anchor.
    expect(
      container.querySelector("[data-node-id='credential-1']"),
    ).not.toBeNull();
    expect(container.querySelector("[data-node-id='host-a1']")).not.toBeNull();
    expect(container.querySelector("[data-node-id='host-b1']")).toBeNull();
  });

  it("clears keyboard focus when its entity leaves the scene", async () => {
    const { graph, projection } = prepare();
    const { container, rerender } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false, onSelectNode: vi.fn() },
    });

    await fireEvent.focus(container.querySelector("[data-node-id='host-a1']")!);
    expect(
      container.querySelector("[data-node-id='service-a1']"),
    ).not.toBeNull();

    // Remove the focused host while the projection still references it.
    await rerender({
      graph: graphContract(
        graph.nodes.filter((node) => node.id !== "host-a1"),
        graph.edges,
      ),
      projection,
      autoFit: false,
      onSelectNode: vi.fn(),
    });
    await flushAsync();

    // Restore the graph. A stale focus would reveal the old neighborhood
    // without any new focus event.
    await rerender({
      graph,
      projection,
      autoFit: false,
      onSelectNode: vi.fn(),
    });
    await flushAsync();

    expect(container.querySelector("[data-node-id='service-a1']")).toBeNull();
  });

  it("places connection and pin controls next to their entity", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        selectedNodeId: "host-a1",
        onTogglePin: vi.fn(),
        onGeometryChange: vi.fn(),
        onSelectNode: vi.fn(),
        onCreateConnection: vi.fn(),
      },
    });

    const host = container.querySelector("[data-node-id='host-a1']")!;
    const handle = container.querySelector(
      "[aria-label='Create connection from Host host-a1']",
    )!;
    const pin = container.querySelector("[data-pin-entity='host-a1']")!;

    // Both controls share the entity's parent and follow it in DOM order, so
    // assistive technology reaches them right after their entity.
    expect(handle.parentElement).toBe(host.parentElement);
    expect(pin.parentElement).toBe(host.parentElement);
    expect(
      host.compareDocumentPosition(handle) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(
      host.compareDocumentPosition(pin) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  it("draws an anchor link for revealed attached context", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        selectedNodeId: "host-a1",
      },
    });

    const links = container.querySelectorAll(".topology-anchor-link");
    expect(links).toHaveLength(1);
    expect(links[0]!.getAttribute("aria-label")).toContain("StoresCredential");
  });

  it("reveals the same lens for keyboard focus as for selection", async () => {
    const { graph, projection } = prepare();
    const selected = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        onSelectNode: vi.fn(),
        selectedNodeId: "host-a1",
      },
    });
    const selectedIds = revealedNodeIds(selected.container);
    selected.unmount();

    const { container } = render(TopologyCanvas, {
      props: { graph, projection, autoFit: false, onSelectNode: vi.fn() },
    });
    expect(container.querySelector("[data-node-id='service-a1']")).toBeNull();

    await fireEvent.focus(container.querySelector("[data-node-id='host-a1']")!);

    expect(revealedNodeIds(container)).toEqual(selectedIds);
    expect(selectedIds).toContain("service-a1");

    await fireEvent.blur(container.querySelector("[data-node-id='host-a1']")!);

    expect(container.querySelector("[data-node-id='service-a1']")).toBeNull();
  });

  it("keeps a pinned lens after the selection moves", async () => {
    const { graph, projection } = prepare();
    const { container, rerender } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        pinnedEntityIds: ["segment-a"],
        selectedNodeId: "host-b1",
        onTogglePin: vi.fn(),
      },
    });

    // The pin keeps segment-a revealed while the selection sits elsewhere.
    expect(
      container.querySelector("[data-node-id='service-a1']"),
    ).not.toBeNull();
    expect(container.querySelector("[data-node-id='host-b1']")).not.toBeNull();
    expect(
      container.querySelector("[data-segment-id='segment-a']")!.classList,
    ).not.toContain("is-dimmed");
    expect(
      container.querySelector("[data-pin-entity='segment-a']"),
    ).not.toBeNull();
    expect(
      screen.queryByRole("button", { name: "Unpin Zone A" }),
    ).not.toBeNull();

    await rerender({
      graph,
      projection,
      autoFit: false,
      pinnedEntityIds: [],
      selectedNodeId: "host-b1",
      onTogglePin: vi.fn(),
    });

    // Unpin returns the neighborhood to the zoom baseline: the revealed
    // service disappears, and the unrelated hosts return to full emphasis.
    expect(container.querySelector("[data-node-id='service-a1']")).toBeNull();
    expect(
      container
        .querySelector("[data-node-id='host-a2']")!
        .classList.contains("is-dimmed"),
    ).toBe(true);
    expect(
      container
        .querySelector("[data-node-id='host-b1']")!
        .classList.contains("is-dimmed"),
    ).toBe(false);
  });

  it("toggles a pin from the selected card", async () => {
    const { graph, projection } = prepare();
    const onTogglePin = vi.fn();
    const { container, rerender } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        selectedNodeId: "host-a1",
        onTogglePin,
      },
    });

    const pin = screen.getByRole("button", { name: "Pin host-a1" });
    expect(pin).toHaveAttribute("aria-pressed", "false");
    await fireEvent.click(pin);

    expect(onTogglePin).toHaveBeenCalledWith("host-a1");

    await rerender({
      graph,
      projection,
      autoFit: false,
      selectedNodeId: "host-a1",
      pinnedEntityIds: ["host-a1"],
      onTogglePin,
    });

    const unpin = screen.getByRole("button", { name: "Unpin host-a1" });
    expect(unpin).toHaveAttribute("aria-pressed", "true");
    expect(
      container.querySelector("[data-node-id='host-a1']")!.classList,
    ).toContain("is-pinned");
  });

  it("clears every pin from the canvas menu", async () => {
    const { graph, projection } = prepare();
    const onClearPins = vi.fn();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        pinnedEntityIds: ["host-a1", "segment-b"],
        onTogglePin: vi.fn(),
        onClearPins,
      },
    });

    expect(
      container.querySelector("[data-node-id='service-a1']"),
    ).not.toBeNull();

    await fireEvent.contextMenu(container.querySelector(".topology-surface")!);
    await fireEvent.click(screen.getByText("Clear pins (2)"));

    expect(onClearPins).toHaveBeenCalledTimes(1);
  });

  it("connects two entities through an exposed keyboard path", async () => {
    const { graph, projection } = prepare();
    const onCreateConnection = vi.fn();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        onGeometryChange: vi.fn(),
        onSelectNode: vi.fn(),
        onCreateConnection,
      },
    });

    const handle = container.querySelector<SVGCircleElement>(
      "[aria-label='Create connection from Host host-a1']",
    )!;
    expect(handle).not.toBeNull();
    // The handle is a sibling of the card, so no interactive control nests.
    expect(handle.parentElement?.closest("[role='button']")).toBeNull();

    await fireEvent.keyDown(handle, { key: "Enter" });

    expect(
      container.querySelector("[data-status='connection-source']"),
    ).not.toBeNull();

    await fireEvent.keyDown(
      container.querySelector("[data-node-id='host-b1']")!,
      { key: "Enter" },
    );

    expect(onCreateConnection).toHaveBeenCalledTimes(1);
    expect(onCreateConnection.mock.calls[0]!.slice(0, 2)).toEqual([
      "host-a1",
      "host-b1",
    ]);
    expect(
      container.querySelector("[data-status='connection-source']"),
    ).toBeNull();
  });

  it("cancels a keyboard connection with Escape", async () => {
    const { graph, projection } = prepare();
    const onCreateConnection = vi.fn();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        onGeometryChange: vi.fn(),
        onSelectNode: vi.fn(),
        onCreateConnection,
      },
    });

    const handle = container.querySelector<SVGCircleElement>(
      "[aria-label='Create connection from Host host-a1']",
    )!;
    await fireEvent.keyDown(handle, { key: "Enter" });
    await fireEvent.keyDown(container.querySelector(".topology-surface")!, {
      key: "Escape",
    });
    await fireEvent.keyDown(
      container.querySelector("[data-node-id='host-b1']")!,
      {
        key: "Enter",
      },
    );

    expect(onCreateConnection).not.toHaveBeenCalled();
    expect(
      container.querySelector("[data-status='connection-source']"),
    ).toBeNull();
  });

  it("keeps dimmed and revealed content in the accessibility tree", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        selectedNodeId: "host-a1",
        onSelectNode: vi.fn(),
      },
    });

    // Dimming is a visual cue. It removes nothing from the accessibility tree,
    // and it never hides revealed content.
    expect(
      container.querySelector("[data-node-id][aria-hidden='true']"),
    ).toBeNull();
    expect(container.querySelector("[data-node-id][hidden]")).toBeNull();
    expect(
      screen.queryByRole("button", { name: /Host host-b1/ }),
    ).not.toBeNull();
    expect(
      screen.queryByRole("group", { name: /Zone B segment/ }),
    ).not.toBeNull();
  });

  it("runs an add request once and acknowledges its token", async () => {
    const { graph, projection } = prepare();
    const onAddNode = vi.fn();
    const onAddRequestHandled = vi.fn();
    const props = {
      graph,
      projection,
      autoFit: false,
      onAddNode,
      onAddRequestHandled,
    };
    const { rerender } = render(TopologyCanvas, { props });
    const request = { type: "Host" as const, token: 1 };

    await rerender({ ...props, addRequest: request });

    expect(onAddNode).toHaveBeenCalledTimes(1);
    expect(onAddRequestHandled).toHaveBeenCalledWith(1);

    // The caller clears the request it acknowledged. A repeated delivery of
    // the same token still creates nothing more.
    await rerender({ ...props, addRequest: { ...request } });

    expect(onAddNode).toHaveBeenCalledTimes(1);
    expect(onAddRequestHandled).toHaveBeenCalledTimes(1);

    await rerender({ ...props, addRequest: { type: "Host", token: 2 } });

    expect(onAddNode).toHaveBeenCalledTimes(2);
    expect(onAddRequestHandled).toHaveBeenLastCalledWith(2);
  });

  it("acknowledges a view command once for each token", async () => {
    const { graph, projection } = prepare();
    const onViewCommandHandled = vi.fn();
    const props = { graph, projection, autoFit: false, onViewCommandHandled };
    const { rerender } = render(TopologyCanvas, { props });
    const command = { kind: "fit" as const, token: 5 };

    await rerender({ ...props, viewCommand: command });
    await rerender({ ...props, viewCommand: { ...command } });

    expect(onViewCommandHandled).toHaveBeenCalledTimes(1);
    expect(onViewCommandHandled).toHaveBeenCalledWith(5);

    await rerender({ ...props, viewCommand: { kind: "fit", token: 6 } });

    expect(onViewCommandHandled).toHaveBeenCalledTimes(2);
  });

  it("pans from attached context and still selects it on a click", async () => {
    const { graph, projection } = prepare();
    const onSelectNode = vi.fn();
    const onClearSelection = vi.fn();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        // Attached context is baseline-hidden, so pin it to keep it drawn.
        pinnedEntityIds: ["credential-1"],
        onSelectNode,
        onClearSelection,
      },
    });
    const surface = container.querySelector(".topology-surface")!;
    const world = container.querySelector(".topology-world")!;
    const context = container.querySelector("[data-node-id='credential-1']")!;
    const before = world.getAttribute("transform");
    assignPointerCapture(surface);

    await fireEvent.pointerDown(context, {
      button: 0,
      isPrimary: true,
      pointerId: 51,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 51,
      clientX: 30,
      clientY: 20,
      buttons: 1,
    });
    await fireEvent.pointerUp(surface, { pointerId: 51 });

    // Attached context is not draggable, so the gesture pans the viewport.
    expect(world.getAttribute("transform")).not.toBe(before);

    // The click that ends the pan must not clear the selection either.
    await fireEvent.click(surface);
    expect(onClearSelection).not.toHaveBeenCalled();

    await fireEvent.click(context);
    expect(onSelectNode).toHaveBeenCalledWith("credential-1");
  });

  it("pans from an Unplaced card and still selects it on a click", async () => {
    const { graph, projection } = prepare();
    const onSelectNode = vi.fn();
    const orphan = hostNode("host-orphan", 900, 400);
    const { container } = render(TopologyCanvas, {
      props: {
        graph: graphContract([...graph.nodes, orphan], graph.edges),
        projection: projectionOf({
          ...projection,
          issues: [
            {
              code: "host_without_segment",
              severity: "warning",
              entity_id: "host-orphan",
              related_ids: [],
            },
          ],
        }),
        autoFit: false,
        onSelectNode,
      },
    });
    const surface = container.querySelector(".topology-surface")!;
    const world = container.querySelector(".topology-world")!;
    const card = container.querySelector("[data-node-id='host-orphan']")!;
    const before = world.getAttribute("transform");
    assignPointerCapture(surface);

    await fireEvent.pointerDown(card, {
      button: 0,
      isPrimary: true,
      pointerId: 61,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 61,
      clientX: 25,
      clientY: 15,
      buttons: 1,
    });
    await fireEvent.pointerUp(surface, { pointerId: 61 });

    expect(world.getAttribute("transform")).not.toBe(before);

    await fireEvent.click(surface);
    await fireEvent.click(card);

    expect(onSelectNode).toHaveBeenCalledWith("host-orphan");
  });

  it("keeps a drag handle out of the pan gesture", async () => {
    const { graph, projection } = prepare();
    const { container } = render(TopologyCanvas, {
      props: {
        graph,
        projection,
        autoFit: false,
        onGeometryChange: vi.fn(),
      },
    });
    const surface = container.querySelector(".topology-surface")!;
    const world = container.querySelector(".topology-world")!;
    const header = container.querySelector(
      "[data-segment-header='segment-a']",
    )!;
    const before = world.getAttribute("transform");
    assignPointerCapture(surface);
    assignPointerCapture(header);

    await fireEvent.pointerDown(header, {
      button: 0,
      isPrimary: true,
      pointerId: 71,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 71,
      clientX: 40,
      clientY: 20,
      buttons: 1,
    });
    await fireEvent.pointerUp(surface, { pointerId: 71 });

    // A drag handle moves geometry. It never pans.
    expect(world.getAttribute("transform")).toBe(before);
  });
});
