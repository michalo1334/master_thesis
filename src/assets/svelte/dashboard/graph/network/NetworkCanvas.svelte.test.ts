import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import { tick } from "svelte";
import NetworkCanvas from "./NetworkCanvas.svelte";
import { EditableGraphDocument } from "../EditableGraphDocument.svelte";
import type { DashboardApi } from "../../dashboard-api";
import type { LoadedGraph } from "../../contract";

vi.stubGlobal(
  "ResizeObserver",
  class {
    observe() {}
    unobserve() {}
    disconnect() {}
  },
);

const originalClientWidth = Object.getOwnPropertyDescriptor(
  window.Element.prototype,
  "clientWidth",
);
const originalClientHeight = Object.getOwnPropertyDescriptor(
  window.Element.prototype,
  "clientHeight",
);

function makeGraph(revisionId = "r1"): LoadedGraph {
  return {
    id: "g1",
    title: "Network",
    revision_id: revisionId,
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    nodes: [
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
    ],
  };
}

function makeSegmentGraph(revisionId = "r1"): LoadedGraph {
  return {
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
        view_data: { x_pos: 0, y_pos: -200 },
      },
      {
        id: "seg-b",
        type: "NetworkSegment",
        data: { name: "LAN", cidr: "10.0.1.0/24" },
        view_data: { x_pos: 400, y_pos: -200 },
      },
      ...makeGraph(revisionId).nodes,
    ],
    edges: [
      ...makeGraph(revisionId).edges,
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
      {
        id: "contains-b",
        type: "Contains",
        from_id: "seg-b",
        to_id: "host-b",
        data: {},
      },
    ],
  };
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

describe("NetworkCanvas", () => {
  let document: EditableGraphDocument;
  let api: DashboardApi & { fetchGraphProjection: ReturnType<typeof vi.fn> };

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
    document.replaceFromLoadedGraph(makeGraph());
    api = { fetchGraphProjection: vi.fn() } as unknown as DashboardApi & {
      fetchGraphProjection: ReturnType<typeof vi.fn>;
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

  it("fetches the projection for the saved clean revision", async () => {
    api.fetchGraphProjection.mockResolvedValue(
      projectionReply([{ id: "flow-1", from_id: "host-a", to_id: "service" }]),
    );

    render(NetworkCanvas, { props: { document, api } });

    await waitFor(() =>
      expect(api.fetchGraphProjection).toHaveBeenCalledWith("r1"),
    );
  });

  it("draws noninteractive operational flows at high zoom", async () => {
    api.fetchGraphProjection.mockResolvedValue(
      projectionReply([{ id: "flow-1", from_id: "host-a", to_id: "service" }]),
    );

    render(NetworkCanvas, { props: { document, api } });

    await waitFor(() =>
      expect(
        screen.getByRole("img", { name: "Operational flow from A to https" }),
      ).toBeInTheDocument(),
    );
  });

  it("renders a segment policy link as a keyboard-selectable button", async () => {
    document.replaceFromLoadedGraph(makeSegmentGraph());
    api.fetchGraphProjection.mockResolvedValue(
      projectionReply([{ id: "flow-1", from_id: "host-a", to_id: "service" }]),
    );

    render(NetworkCanvas, { props: { document, api } });

    const zoomOut = screen.getByRole("button", { name: "Zoom out" });
    for (let i = 0; i < 5; i++) await fireEvent.click(zoomOut);

    const link = screen.getByRole("button", { name: "Segment reachability" });
    expect(link).toHaveAttribute("tabindex", "0");
    expect(
      screen.queryByRole("img", { name: /Operational flow from/ }),
    ).not.toBeInTheDocument();

    await fireEvent.keyDown(link, { key: "Enter" });
    expect(document.canvasSelection).toEqual({
      kind: "edge",
      edgeId: "policy",
    });

    document.clearSelection();
    await fireEvent.keyDown(link, { key: " " });
    expect(document.canvasSelection).toEqual({
      kind: "edge",
      edgeId: "policy",
    });

    document.clearSelection();
    await fireEvent.click(link);
    expect(document.canvasSelection).toEqual({
      kind: "edge",
      edgeId: "policy",
    });
  });

  it("keeps operational flows noninteractive: no selection, edit, or delete path", async () => {
    document.replaceFromLoadedGraph(makeSegmentGraph());
    api.fetchGraphProjection.mockResolvedValue(
      projectionReply([{ id: "flow-1", from_id: "host-a", to_id: "service" }]),
    );

    render(NetworkCanvas, { props: { document, api } });

    const flow = await screen.findByRole("img", {
      name: "Operational flow from A to https",
    });
    expect(flow).not.toHaveAttribute("tabindex");
    expect(flow.querySelector('[role="button"]')).toBeNull();

    await fireEvent.click(flow);
    expect(document.canvasSelection.kind).toBe("none");
  });

  it("shows a stale notice while the document is dirty", async () => {
    api.fetchGraphProjection.mockResolvedValue(projectionReply([]));

    render(NetworkCanvas, { props: { document, api } });
    await waitFor(() =>
      expect(api.fetchGraphProjection).toHaveBeenCalledWith("r1"),
    );
    expect(screen.queryByText(/stale/i)).not.toBeInTheDocument();

    document.graph = { ...document.graph };
    await tick();

    expect(
      screen.getByText("Reachability flows are stale. Save to refresh."),
    ).toBeInTheDocument();
  });

  it("refetches the projection after a successful save", async () => {
    api.fetchGraphProjection.mockResolvedValue(projectionReply([]));

    render(NetworkCanvas, { props: { document, api } });
    await waitFor(() =>
      expect(api.fetchGraphProjection).toHaveBeenCalledWith("r1"),
    );

    document.replaceFromSaveReply(makeGraph("r2"));
    await waitFor(() =>
      expect(api.fetchGraphProjection).toHaveBeenCalledWith("r2"),
    );
    await waitFor(() =>
      expect(screen.queryByText(/stale/i)).not.toBeInTheDocument(),
    );
  });

  it("does not render prior flows when the refetch fails after a revision change", async () => {
    api.fetchGraphProjection
      .mockResolvedValueOnce(
        projectionReply([
          { id: "flow-1", from_id: "host-a", to_id: "service" },
        ]),
      )
      .mockRejectedValueOnce(new Error("projection failed"));

    render(NetworkCanvas, { props: { document, api } });
    await waitFor(() =>
      expect(
        screen.getByRole("img", { name: "Operational flow from A to https" }),
      ).toBeInTheDocument(),
    );

    document.replaceFromSaveReply(makeGraph("r2"));
    await waitFor(() =>
      expect(api.fetchGraphProjection).toHaveBeenCalledWith("r2"),
    );

    await waitFor(() =>
      expect(
        screen.queryByRole("img", {
          name: "Operational flow from A to https",
        }),
      ).not.toBeInTheDocument(),
    );
    expect(
      screen.getByText("Reachability projection unavailable."),
    ).toBeInTheDocument();
  });
});
