import type { GraphContract } from "../../../contracts.generated/graph";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/svelte";
import NetworkCanvas from "./NetworkCanvas.svelte";
import { EditableGraphDocument } from "../EditableGraphDocument.svelte";
import type { DashboardApi } from "../../dashboard-api";
function graph(): GraphContract {
  return {
    id: "graph",
    title: "Network",
    revision_id: "r1",
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    nodes: [
      {
        id: "dmz",
        type: "NetworkSegment",
        data: { name: "DMZ", cidr: "10.0.0.0/24" },
        view_data: { x_pos: 200, y_pos: 200 },
      },
      {
        id: "lan",
        type: "NetworkSegment",
        data: { name: "LAN", cidr: "10.0.1.0/24" },
        view_data: { x_pos: 600, y_pos: 200 },
      },
      {
        id: "host-a",
        type: "Host",
        data: { name: "A" },
        view_data: { x_pos: 100, y_pos: 180 },
      },
      {
        id: "host-b",
        type: "Host",
        data: { name: "B" },
        view_data: { x_pos: 480, y_pos: 180 },
      },
      {
        id: "service-a",
        type: "Service",
        data: { name: "https", port: 443, protocol: "tcp" },
        view_data: { x_pos: 100, y_pos: 180 },
      },
      {
        id: "service-b",
        type: "Service",
        data: { name: "ssh", port: 22, protocol: "tcp" },
        view_data: { x_pos: 480, y_pos: 180 },
      },
    ],
    edges: [
      {
        id: "contains-a",
        type: "Contains",
        from_id: "dmz",
        to_id: "host-a",
        data: {},
      },
      {
        id: "contains-b",
        type: "Contains",
        from_id: "lan",
        to_id: "host-b",
        data: {},
      },
      {
        id: "runs-a",
        type: "Runs",
        from_id: "host-a",
        to_id: "service-a",
        data: {},
      },
      {
        id: "runs-b",
        type: "Runs",
        from_id: "host-b",
        to_id: "service-b",
        data: {},
      },
      {
        id: "policy",
        type: "SegmentReachability",
        from_id: "dmz",
        to_id: "lan",
        data: { protocol: "tcp" },
      },
    ],
  };
}

function api(
  flows: { id: string; from_id: string; to_id: string }[] = [],
): DashboardApi {
  return {
    fetchGraphProjection: vi.fn().mockResolvedValue({
      status: "ok",
      segments: [],
      hosts: [],
      policy_links: [],
      operational_flows: flows,
    }),
  } as unknown as DashboardApi;
}

function prepare(): { document: EditableGraphDocument; api: DashboardApi } {
  const document = new EditableGraphDocument();
  document.replaceFromLoadedGraph(graph());
  return { document, api: api() };
}

describe("NetworkCanvas", () => {
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

  it("expands every host in multiple zones and provides global disclosure controls", async () => {
    const { document, api: dashboardApi } = prepare();
    const { container } = render(NetworkCanvas, {
      props: { document, api: dashboardApi },
    });

    await fireEvent.click(
      screen.getByRole("button", { name: "Expand all zones" }),
    );
    expect(
      container.querySelectorAll("[data-testid='host-node']"),
    ).toHaveLength(2);
    expect(
      screen.getByRole("button", { name: "Collapse DMZ" }),
    ).toHaveAttribute("aria-expanded", "true");
    expect(
      screen.getByRole("button", { name: "Collapse LAN" }),
    ).toHaveAttribute("aria-expanded", "true");

    await fireEvent.click(
      screen.getByRole("button", { name: "Collapse all zones" }),
    );
    expect(
      container.querySelectorAll("[data-testid='host-node']"),
    ).toHaveLength(0);
  });

  it("keeps persisted zone and host positions unchanged by disclosure", async () => {
    const { document, api: dashboardApi } = prepare();
    const { container } = render(NetworkCanvas, {
      props: { document, api: dashboardApi },
    });
    const before = document.graph.nodes.map((node) => ({ ...node.view_data }));
    const zone = container.querySelector("[data-zone-id='dmz']")!;
    const center = [zone.getAttribute("cx"), zone.getAttribute("cy")];

    await fireEvent.click(screen.getByRole("button", { name: "Expand DMZ" }));
    await fireEvent.click(screen.getByRole("button", { name: "Collapse DMZ" }));
    expect([zone.getAttribute("cx"), zone.getAttribute("cy")]).toEqual(center);
    expect(document.graph.nodes.map((node) => node.view_data)).toEqual(before);
  });

  it("keeps multiple host details open", async () => {
    const { document, api: dashboardApi } = prepare();
    const { container } = render(NetworkCanvas, {
      props: { document, api: dashboardApi },
    });
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand all zones" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand details for host A" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand details for host B" }),
    );
    expect(
      container.querySelectorAll("[data-testid='service-row']"),
    ).toHaveLength(2);
  });

  it("keeps node selection, policy selection, pan, and zoom controls working", async () => {
    const { document, api: dashboardApi } = prepare();
    const { container } = render(NetworkCanvas, {
      props: { document, api: dashboardApi },
    });
    const surface = container.querySelector("svg.network-surface")!;
    Object.assign(surface, {
      setPointerCapture: () => {},
      hasPointerCapture: () => true,
      releasePointerCapture: () => {},
    });

    await fireEvent.click(
      screen.getByRole("button", { name: "Segment reachability" }),
    );
    expect(document.canvasSelection).toEqual({
      kind: "edge",
      edgeId: "policy",
    });
    await fireEvent.pointerDown(surface, {
      button: 0,
      isPrimary: true,
      pointerId: 1,
      clientX: 10,
      clientY: 10,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 1,
      clientX: 30,
      clientY: 20,
    });
    expect(surface.querySelector(":scope > g")).toHaveAttribute(
      "transform",
      "translate(20 10) scale(1)",
    );
    await fireEvent.click(screen.getByRole("button", { name: "Zoom in" }));
    expect(screen.getByLabelText("Zoom level")).toHaveTextContent("110%");
  });

  it("selects a service from an expanded host", async () => {
    const { document, api: dashboardApi } = prepare();
    render(NetworkCanvas, { props: { document, api: dashboardApi } });

    await fireEvent.click(screen.getByRole("button", { name: "Expand DMZ" }));
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand details for host A" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Service https" }),
    );
    expect(document.canvasSelection).toEqual({
      kind: "node",
      nodeId: "service-a",
    });
  });

  it("persists zoom-aware host and zone drags", async () => {
    const { document, api: dashboardApi } = prepare();
    const { container } = render(NetworkCanvas, {
      props: { document, api: dashboardApi },
    });
    await fireEvent.click(screen.getByRole("button", { name: "Expand DMZ" }));
    const surface = container.querySelector("svg")!;
    const host = container.querySelector("[data-host-id='host-a']")!;
    const zone = container.querySelector("[data-testid='network-zone']")!;
    for (const element of [host, zone])
      Object.assign(element, {
        setPointerCapture: () => {},
        hasPointerCapture: () => true,
        releasePointerCapture: () => {},
      });

    await fireEvent.pointerDown(host, {
      button: 0,
      isPrimary: true,
      pointerId: 1,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 1,
      clientX: 20,
      clientY: 10,
    });
    await fireEvent.pointerUp(surface, { pointerId: 1 });
    expect(
      document.graph.nodes.find((node) => node.id === "host-a")!.view_data,
    ).toEqual({ x_pos: 120, y_pos: 190 });

    await fireEvent.pointerDown(zone, {
      button: 0,
      isPrimary: true,
      pointerId: 2,
      clientX: 0,
      clientY: 0,
    });
    await fireEvent.pointerMove(surface, {
      pointerId: 2,
      clientX: 10,
      clientY: 20,
    });
    await fireEvent.pointerUp(surface, { pointerId: 2 });
    expect(
      document.graph.nodes.find((node) => node.id === "dmz")!.view_data,
    ).toEqual({ x_pos: 210, y_pos: 220 });
    expect(
      document.graph.nodes.find((node) => node.id === "host-a")!.view_data,
    ).toEqual({ x_pos: 130, y_pos: 210 });
  });

  it("shows no operational flows without a selection after fetching", async () => {
    const { document } = prepare();
    const dashboardApi = api([
      { id: "one", from_id: "host-a", to_id: "service-b" },
    ]);
    const { container } = render(NetworkCanvas, {
      props: { document, api: dashboardApi },
    });
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand all zones" }),
    );

    await waitFor(() =>
      expect(dashboardApi.fetchGraphProjection).toHaveBeenCalledWith("r1"),
    );
    expect(
      within(container).queryAllByRole("img", { name: /Operational flow/ }),
    ).toHaveLength(0);
  });

  it("shows incoming and outgoing operational flows for the selected host", async () => {
    const { document } = prepare();
    const dashboardApi = api([
      { id: "one", from_id: "host-a", to_id: "service-b" },
      { id: "two", from_id: "host-a", to_id: "service-b" },
      { id: "back", from_id: "host-b", to_id: "service-a" },
    ]);
    const { container } = render(NetworkCanvas, {
      props: { document, api: dashboardApi },
    });
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand all zones" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Select host A" }),
    );
    const flows = await within(container).findAllByRole("img", {
      name: /Operational flow/,
    });
    expect(flows).toHaveLength(2);
    expect(flows[0]!.querySelector("path")!.getAttribute("d")).toContain("Q");
    expect(flows[0]!.querySelector("path")!.getAttribute("d")).not.toBe(
      flows[1]!.querySelector("path")!.getAttribute("d"),
    );
  });

  it("resolves a selected service to its host's operational flows", async () => {
    const { document } = prepare();
    const dashboardApi = api([
      { id: "outgoing", from_id: "host-a", to_id: "service-b" },
      { id: "incoming", from_id: "host-b", to_id: "service-a" },
    ]);
    const { container } = render(NetworkCanvas, {
      props: { document, api: dashboardApi },
    });
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand all zones" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand details for host A" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Service https" }),
    );

    expect(
      await within(container).findAllByRole("img", {
        name: /Operational flow/,
      }),
    ).toHaveLength(2);
  });

  it("hides operational flows when the selection changes to another node, an edge, or none", async () => {
    const { document } = prepare();
    const dashboardApi = api([
      { id: "one", from_id: "host-a", to_id: "service-b" },
    ]);
    const { container } = render(NetworkCanvas, {
      props: { document, api: dashboardApi },
    });
    await fireEvent.click(
      screen.getByRole("button", { name: "Expand all zones" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Select host A" }),
    );
    await within(container).findAllByRole("img", { name: /Operational flow/ });

    await fireEvent.click(screen.getByRole("button", { name: "Select DMZ" }));
    expect(
      within(container).queryAllByRole("img", { name: /Operational flow/ }),
    ).toHaveLength(0);

    await fireEvent.click(
      screen.getByRole("button", { name: "Segment reachability" }),
    );
    expect(
      within(container).queryAllByRole("img", { name: /Operational flow/ }),
    ).toHaveLength(0);

    document.clearSelection();
    expect(
      within(container).queryAllByRole("img", { name: /Operational flow/ }),
    ).toHaveLength(0);
  });
});
