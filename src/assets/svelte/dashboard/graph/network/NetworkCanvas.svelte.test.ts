import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/svelte";
import { tick } from "svelte";
import NetworkCanvas from "./NetworkCanvas.svelte";
import { EditableGraphDocument } from "../EditableGraphDocument.svelte";
import type { DashboardApi } from "../../dashboard-api";
import type { LoadedGraph } from "../../contract";

const originalClientWidth = Object.getOwnPropertyDescriptor(
  window.Element.prototype,
  "clientWidth",
);
const originalClientHeight = Object.getOwnPropertyDescriptor(
  window.Element.prototype,
  "clientHeight",
);

function graph(
  revisionId = "r1",
  dmzHostCount = 1,
  colocatedSegments = false,
): LoadedGraph {
  const result: LoadedGraph = {
    id: "g1",
    title: "Network",
    revision_id: revisionId,
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    nodes: [
      {
        id: "seg-a",
        type: "NetworkSegment",
        data: { name: "DMZ", cidr: "10.0.0.0/24" },
        view_data: { x_pos: 200, y_pos: 200 },
      },
      {
        id: "seg-b",
        type: "NetworkSegment",
        data: { name: "LAN", cidr: "10.0.1.0/24" },
        view_data: { x_pos: colocatedSegments ? 200 : 600, y_pos: 200 },
      },
      {
        id: "host-a",
        type: "Host",
        data: { name: "A" },
        view_data: { x_pos: 0, y_pos: 0 },
      },
      {
        id: "host-b",
        type: "Host",
        data: { name: "B" },
        view_data: { x_pos: 400, y_pos: 0 },
      },
      {
        id: "service",
        type: "Service",
        data: { name: "https", port: 443, protocol: "tcp" },
        view_data: { x_pos: 0, y_pos: 0 },
      },
    ],
    edges: [
      {
        id: "runs",
        type: "Runs",
        from_id: "host-a",
        to_id: "service",
        data: {},
      },
      {
        id: "policy",
        type: "SegmentReachability",
        from_id: "seg-a",
        to_id: "seg-b",
        data: { protocol: "tcp" },
      },
      {
        id: "contains-a",
        type: "Contains",
        from_id: "seg-a",
        to_id: "host-a",
        data: {},
      },
    ],
  };

  for (let index = 2; index <= dmzHostCount; index++) {
    result.nodes.push({
      id: `host-${index}`,
      type: "Host",
      data: { name: `Host ${index}` },
      view_data: { x_pos: index * 40, y_pos: 0 },
    });
    result.edges.push({
      id: `contains-${index}`,
      type: "Contains",
      from_id: "seg-a",
      to_id: `host-${index}`,
      data: {},
    });
  }
  return result;
}

function projectionReply(
  flows: { id: string; from_id: string; to_id: string }[],
) {
  return {
    status: "ok" as const,
    segments: [],
    hosts: [],
    policy_links: [],
    operational_flows: flows,
  };
}

function addVulnerability(result: LoadedGraph): void {
  result.nodes.push({
    id: "vulnerability",
    type: "Vulnerability",
    data: {
      identifier: "CVE-2026-1",
      exploit_probability: 0.5,
      cvss: {} as never,
    },
    view_data: { x_pos: 0, y_pos: 0 },
  });
  result.edges.push({
    id: "has-vulnerability",
    type: "HasVulnerability",
    from_id: "service",
    to_id: "vulnerability",
    data: { granted_privilege: "user", required_privilege: "none" },
  });
}

function hostBounds(host: Element) {
  const [, x, y] = host
    .getAttribute("transform")!
    .match(/translate\(([-\d.]+) ([-\d.]+)\)/)!;
  return {
    x: Number(x),
    y: Number(y),
    width: 128,
    height: Number(host.getAttribute("data-card-height")),
  };
}

async function openOutline(): Promise<HTMLElement> {
  await fireEvent.click(screen.getByText("Network outline"));
  return screen.getByText("Network outline").closest("details") as HTMLElement;
}

describe("NetworkCanvas", () => {
  let document: EditableGraphDocument;
  let api: DashboardApi & {
    fetchGraphProjection: ReturnType<typeof vi.fn>;
    createConnectionDraft: ReturnType<typeof vi.fn>;
  };

  beforeEach(() => {
    Object.defineProperty(window.Element.prototype, "clientWidth", {
      configurable: true,
      value: 1200,
    });
    Object.defineProperty(window.Element.prototype, "clientHeight", {
      configurable: true,
      value: 800,
    });
    document = new EditableGraphDocument();
    document.replaceFromLoadedGraph(graph());
    api = {
      fetchGraphProjection: vi.fn().mockResolvedValue(projectionReply([])),
      createConnectionDraft: vi.fn(),
    } as unknown as DashboardApi & {
      fetchGraphProjection: ReturnType<typeof vi.fn>;
      createConnectionDraft: ReturnType<typeof vi.fn>;
    };
  });

  afterEach(() => {
    cleanup();
    if (originalClientWidth)
      Object.defineProperty(
        window.Element.prototype,
        "clientWidth",
        originalClientWidth,
      );
    if (originalClientHeight)
      Object.defineProperty(
        window.Element.prototype,
        "clientHeight",
        originalClientHeight,
      );
  });

  it("renders non-nested SVG zone glyphs and pointer-selectable ovals", async () => {
    const { container } = render(NetworkCanvas, { props: { document, api } });
    const zone = container.querySelector("[data-testid='network-zone']")!;
    const glyph = zone.querySelector("[data-testid='zone-glyph']")!;

    expect(
      container.querySelectorAll("ellipse[data-testid='zone-oval']"),
    ).toHaveLength(3);
    expect(
      container.querySelectorAll("[data-testid='zone-glyph']"),
    ).toHaveLength(3);
    expect(zone).not.toHaveAttribute("role");
    expect(glyph).toHaveAttribute("role", "button");
    expect(container.querySelector("foreignObject")).toBeNull();

    await fireEvent.pointerDown(
      zone.querySelector("[data-testid='zone-oval']")!,
    );
    expect(document.canvasSelection).toEqual({ kind: "node", nodeId: "seg-a" });
  });

  it("renders hosts in batches and expands through the visible outline", async () => {
    document.replaceFromLoadedGraph(graph("r1", 8));
    const { container } = render(NetworkCanvas, { props: { document, api } });
    const outline = await openOutline();

    await fireEvent.click(
      within(outline).getByRole("button", { name: "Expand DMZ" }),
    );
    expect(
      container.querySelectorAll("[data-testid='host-node']"),
    ).toHaveLength(6);
    const glyph = screen.getByRole("button", {
      name: "Show 2 more hosts in DMZ zone",
    });
    const oval = glyph.closest(".network-zone")!.querySelector("ellipse")!;
    const initialRadius = oval.getAttribute("ry");
    expect(glyph).toHaveTextContent("+2");
    expect(
      within(outline).getByRole("button", { name: "Show more hosts" }),
    ).toBeInTheDocument();

    await fireEvent.click(
      within(outline).getByRole("button", { name: "Show more hosts" }),
    );
    expect(
      container.querySelectorAll("[data-testid='host-node']"),
    ).toHaveLength(8);
    expect(oval.getAttribute("ry")).not.toBe(initialRadius);
  });

  it("expands one zone and shows its SVG host nodes regardless of zoom", async () => {
    const { container } = render(NetworkCanvas, { props: { document, api } });

    const outline = await openOutline();
    await fireEvent.click(
      within(outline).getByRole("button", { name: "Expand DMZ" }),
    );
    expect(
      container.querySelectorAll("[data-testid='host-node']"),
    ).toHaveLength(1);
    for (let index = 0; index < 5; index++)
      await fireEvent.click(screen.getByRole("button", { name: "Zoom out" }));
    expect(
      container.querySelectorAll("[data-testid='host-node']"),
    ).toHaveLength(1);
    expect(
      within(outline).getByRole("button", { name: "Expand LAN" }),
    ).toBeInTheDocument();
  });

  it("discloses one SVG host card at a time and selects its service and CVE", async () => {
    const graphWithDetails = graph("r1", 2);
    addVulnerability(graphWithDetails);
    graphWithDetails.nodes.push({
      id: "service-2",
      type: "Service",
      data: { name: "ssh", port: 22, protocol: "tcp" },
      view_data: { x_pos: 0, y_pos: 0 },
    });
    graphWithDetails.edges.push({
      id: "runs-2",
      type: "Runs",
      from_id: "host-2",
      to_id: "service-2",
      data: {},
    });
    document.replaceFromLoadedGraph(graphWithDetails);
    const { container } = render(NetworkCanvas, { props: { document, api } });
    const outline = await openOutline();

    await fireEvent.click(
      within(outline).getByRole("button", { name: "Expand DMZ" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand details for host A" }),
    );
    expect(
      container.querySelectorAll("[data-testid='service-row']"),
    ).toHaveLength(1);
    expect(container.querySelectorAll("[data-testid='cve-row']")).toHaveLength(
      1,
    );
    expect(container.querySelector("foreignObject")).toBeNull();

    await fireEvent.click(
      screen.getByRole("button", { name: "Service https" }),
    );
    expect(document.canvasSelection).toEqual({
      kind: "node",
      nodeId: "service",
    });
    await fireEvent.click(
      screen.getByRole("button", { name: "CVE CVE-2026-1" }),
    );
    expect(document.canvasSelection).toEqual({
      kind: "node",
      nodeId: "vulnerability",
    });

    await fireEvent.click(
      screen.getByRole("button", { name: "Expand details for host Host 2" }),
    );
    expect(
      container.querySelectorAll("[data-testid='service-row']"),
    ).toHaveLength(1);
    expect(
      screen.queryByRole("button", { name: "CVE CVE-2026-1" }),
    ).not.toBeInTheDocument();
  });

  it("lays out variable-height host cards without overlap and contains every card corner", async () => {
    const graphWithDetails = graph("r1", 6);
    addVulnerability(graphWithDetails);
    document.replaceFromLoadedGraph(graphWithDetails);
    const { container } = render(NetworkCanvas, { props: { document, api } });
    const outline = await openOutline();

    await fireEvent.click(
      within(outline).getByRole("button", { name: "Expand DMZ" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand details for host A" }),
    );
    const hosts = [...container.querySelectorAll("[data-testid='host-node']")];
    const bounds = hosts.map(hostBounds);
    for (let index = 0; index < bounds.length; index++) {
      for (let other = index + 1; other < bounds.length; other++) {
        const first = bounds[index]!;
        const second = bounds[other]!;
        expect(
          first.x + first.width <= second.x ||
            second.x + second.width <= first.x ||
            first.y + first.height <= second.y ||
            second.y + second.height <= first.y,
        ).toBe(true);
      }
    }

    const oval = container.querySelector("[data-zone-id='seg-a']")!;
    const cx = Number(oval.getAttribute("cx"));
    const cy = Number(oval.getAttribute("cy"));
    const rx = Number(oval.getAttribute("rx"));
    const ry = Number(oval.getAttribute("ry"));
    const maxX = Math.max(
      ...bounds.flatMap((card) => [
        Math.abs(card.x - cx),
        Math.abs(card.x + card.width - cx),
      ]),
    );
    const maxY = Math.max(
      ...bounds.flatMap((card) => [
        Math.abs(card.y - cy),
        Math.abs(card.y + card.height - cy),
      ]),
    );
    for (const card of bounds) {
      for (const x of [card.x, card.x + card.width]) {
        for (const y of [card.y, card.y + card.height]) {
          expect(
            ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2,
          ).toBeLessThanOrEqual(1);
        }
      }
    }
    expect(rx).toBeLessThan((maxX + 12) * 2);
    expect(ry).toBeLessThan((maxY + 12) * 2);
  });

  it("clears host detail when its zone collapses or another zone expands", async () => {
    const graphWithDetails = graph();
    addVulnerability(graphWithDetails);
    document.replaceFromLoadedGraph(graphWithDetails);
    const { container } = render(NetworkCanvas, { props: { document, api } });
    const outline = await openOutline();

    await fireEvent.click(
      within(outline).getByRole("button", { name: "Expand DMZ" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand details for host A" }),
    );
    await fireEvent.click(
      within(outline).getByRole("button", { name: "Collapse DMZ" }),
    );
    expect(container.querySelector("[data-testid='service-row']")).toBeNull();

    await fireEvent.click(
      within(outline).getByRole("button", { name: "Expand DMZ" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand details for host A" }),
    );
    await fireEvent.click(
      within(outline).getByRole("button", { name: "Expand LAN" }),
    );
    expect(container.querySelector("[data-testid='service-row']")).toBeNull();
  });

  it("provides cursor-safe zoom plus fit and reset controls", async () => {
    const { container } = render(NetworkCanvas, { props: { document, api } });
    const zoom = screen.getByLabelText("Zoom level");
    const surface = container.querySelector("svg.network-surface")!;

    await fireEvent.click(screen.getByRole("button", { name: "Zoom in" }));
    expect(zoom).toHaveTextContent("110%");
    await fireEvent.wheel(surface, { deltaY: -1, clientX: 400, clientY: 300 });
    expect(zoom).toHaveTextContent("120%");
    await fireEvent.click(screen.getByRole("button", { name: "Fit" }));
    expect(zoom).not.toHaveTextContent("120%");
    await fireEvent.click(screen.getByRole("button", { name: "Reset" }));
    expect(zoom).toHaveTextContent("100%");
  });

  it("pans from blank SVG space", async () => {
    const { container } = render(NetworkCanvas, { props: { document, api } });
    const surface = container.querySelector("svg.network-surface")!;
    const content = surface.querySelector(":scope > g")!;
    Object.assign(surface, {
      setPointerCapture: () => {},
      hasPointerCapture: () => true,
      releasePointerCapture: () => {},
    });

    await fireEvent.pointerDown(surface, {
      button: 0,
      isPrimary: true,
      pointerId: 1,
      clientX: 100,
      clientY: 100,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 1,
      clientX: 140,
      clientY: 130,
    });
    expect(content).toHaveAttribute("transform", "translate(40 30) scale(1)");
  });

  it("layers selectable policy paths behind zone ovals", async () => {
    const { container } = render(NetworkCanvas, { props: { document, api } });
    const policy = screen.getByRole("button", { name: "Segment reachability" });
    const oval = container.querySelector("[data-testid='zone-oval']")!;

    expect(
      policy.compareDocumentPosition(oval) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    await fireEvent.click(policy);
    expect(document.canvasSelection).toEqual({
      kind: "edge",
      edgeId: "policy",
    });
  });

  it("renders a finite policy path for colocated zones", () => {
    document.replaceFromLoadedGraph(graph("r1", 1, true));
    const { container } = render(NetworkCanvas, { props: { document, api } });
    const path = container.querySelector("[data-testid='policy-link'] path")!;

    expect(path).toHaveAttribute("d");
    expect(path.getAttribute("d")).not.toMatch(/NaN|Infinity/);
  });

  it("selects visible hosts and assigns the selected unassigned host through the toolbar", async () => {
    const edge = {
      id: "contains-b",
      type: "Contains" as const,
      from_id: "seg-b",
      to_id: "host-b",
      data: {},
    };
    api.createConnectionDraft.mockResolvedValue({ status: "ok", edge });
    const { container } = render(NetworkCanvas, { props: { document, api } });

    const outline = await openOutline();
    await fireEvent.click(
      within(outline).getByRole("button", { name: "Expand Unassigned" }),
    );
    const host = container.querySelector("[data-host-id='host-b']")!;
    expect(host).not.toHaveAttribute("role");
    expect(host).not.toHaveAttribute("tabindex");
    await fireEvent.click(host);
    expect(document.canvasSelection).toEqual({
      kind: "node",
      nodeId: "host-b",
    });
    await fireEvent.change(
      screen.getByLabelText("Assign selected host to a segment"),
      { target: { value: "seg-b" } },
    );
    await waitFor(() =>
      expect(api.createConnectionDraft).toHaveBeenCalledWith(
        expect.objectContaining({ source_id: "seg-b", target_id: "host-b" }),
      ),
    );
  });

  it("fetches the projection and shows operational flows only when both hosts are visible", async () => {
    const graphWithHiddenTarget = graph("r1", 8);
    graphWithHiddenTarget.nodes.push({
      id: "service-hidden",
      type: "Service",
      data: { name: "ssh", port: 22, protocol: "tcp" },
      view_data: { x_pos: 0, y_pos: 0 },
    });
    graphWithHiddenTarget.edges.push({
      id: "runs-hidden",
      type: "Runs",
      from_id: "host-8",
      to_id: "service-hidden",
      data: {},
    });
    document.replaceFromLoadedGraph(graphWithHiddenTarget);
    api.fetchGraphProjection.mockResolvedValue(
      projectionReply([
        { id: "flow-1", from_id: "host-a", to_id: "service-hidden" },
      ]),
    );
    render(NetworkCanvas, { props: { document, api } });

    await waitFor(() =>
      expect(api.fetchGraphProjection).toHaveBeenCalledWith("r1"),
    );
    expect(
      screen.queryByRole("img", { name: /Operational flow/ }),
    ).not.toBeInTheDocument();
    const outline = await openOutline();
    await fireEvent.click(
      within(outline).getByRole("button", { name: "Expand DMZ" }),
    );
    expect(
      screen.queryByRole("img", { name: "Operational flow from A to ssh" }),
    ).not.toBeInTheDocument();
    await fireEvent.click(
      within(outline).getByRole("button", { name: "Show more hosts" }),
    );
    expect(
      screen.getByRole("img", { name: "Operational flow from A to ssh" }),
    ).toBeInTheDocument();
  });

  it("shows stale state and clears prior flows when a replacement projection fails", async () => {
    api.fetchGraphProjection
      .mockResolvedValueOnce(
        projectionReply([
          { id: "flow-1", from_id: "host-a", to_id: "service" },
        ]),
      )
      .mockRejectedValueOnce(new Error("projection failed"));
    render(NetworkCanvas, { props: { document, api } });
    await waitFor(() =>
      expect(api.fetchGraphProjection).toHaveBeenCalledWith("r1"),
    );
    document.graph = { ...document.graph };
    await tick();
    expect(
      screen.getByText("Reachability flows are stale. Save to refresh."),
    ).toBeInTheDocument();

    document.replaceFromSaveReply(graph("r2"));
    await waitFor(() =>
      expect(api.fetchGraphProjection).toHaveBeenCalledWith("r2"),
    );
    expect(
      screen.getByText("Reachability projection unavailable."),
    ).toBeInTheDocument();
  });
});
