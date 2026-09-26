import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import { tick } from "svelte";
import EditableCanvas from "./EditableCanvas.svelte";
import { EditableGraphDocument } from "../EditableGraphDocument.svelte";
import type { DashboardApi } from "../../dashboard-api";
import {
  buildTopologyFixture,
  NO_PLACEMENT_ENTITY_ID,
  PLACEMENT_ISSUE_ENTITY_ID,
} from "../unified/topology-test-fixture";
import {
  credentialNode,
  reachabilityEdge,
} from "../__tests__/topology-fixtures";

function makeApi(): DashboardApi {
  return {
    fetchGraphConnectivity: vi.fn().mockResolvedValue({ rules: [] }),
    // A draft request that never settles keeps the projection pending.
    projectTopologyDraft: vi.fn(() => new Promise(() => {})),
    createNodeDraft: vi.fn().mockResolvedValue({ status: "ok", node: null }),
  } as unknown as DashboardApi;
}

function makeDocument(api: DashboardApi): EditableGraphDocument {
  const { graph, projection } = buildTopologyFixture();
  const doc = new EditableGraphDocument("Test");
  doc.attachApi(api);
  doc.replaceFromLoadedGraph(
    { ...graph, revision_id: "revision-1" },
    projection,
  );
  return doc;
}

function renderCanvas() {
  const api = makeApi();
  const document = makeDocument(api);
  const result = render(EditableCanvas, { props: { document, api } });
  return { api, document, ...result };
}

/** Authored positions change when Arrange applies the deterministic layout. */
function positions(document: EditableGraphDocument): Record<string, string> {
  return Object.fromEntries(
    document.graph.nodes.map((node) => [
      node.id,
      `${node.view_data.x_pos},${node.view_data.y_pos}`,
    ]),
  );
}

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

describe("EditableCanvas topology controls", () => {
  it("shows the topology toolbar above the canvas", () => {
    renderCanvas();

    expect(
      screen.getByRole("toolbar", { name: "Topology actions" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Add entity" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("combobox", { name: "Search topology" }),
    ).toBeInTheDocument();
  });

  it("arranges geometry without requesting a new projection", async () => {
    const { api, document } = renderCanvas();
    const before = positions(document);

    await fireEvent.click(screen.getByRole("button", { name: "Arrange" }));

    expect(positions(document)).not.toEqual(before);
    expect(api.projectTopologyDraft).not.toHaveBeenCalled();
    expect(document.projectionStatus).toBe("ready");
  });

  it("focuses the canvas entity a search result names", async () => {
    const { document } = renderCanvas();

    await fireEvent.input(
      screen.getByRole("combobox", { name: "Search topology" }),
      { target: { value: "nginx" } },
    );
    await fireEvent.click(
      await screen.findByRole("option", {
        name: "nginx, Zone A / web-1 / nginx",
      }),
    );

    expect(document.canvasSelection).toEqual({ kind: "node", nodeId: "nginx" });
  });

  it("runs an add request once across a canvas remount", async () => {
    const { api, document, unmount } = renderCanvas();

    await fireEvent.click(screen.getByRole("button", { name: "Add entity" }));
    await fireEvent.click(
      await screen.findByRole("menuitem", { name: "Host" }),
    );

    expect(api.createNodeDraft).toHaveBeenCalledTimes(1);

    // The canvas unmounts and mounts again. A command it already ran must not
    // run again, and the toolbar must still work afterwards.
    unmount();
    render(EditableCanvas, { props: { document, api } });

    expect(api.createNodeDraft).toHaveBeenCalledTimes(1);

    await fireEvent.click(screen.getByRole("button", { name: "Add entity" }));
    await fireEvent.click(
      await screen.findByRole("menuitem", { name: "Host" }),
    );

    expect(api.createNodeDraft).toHaveBeenCalledTimes(2);
  });

  it("opens the Unplaced tray from the count and selects an entry", async () => {
    const { document } = renderCanvas();

    await fireEvent.click(
      screen.getByRole("button", { name: "Unplaced entities (3)" }),
    );

    expect(
      screen.getByRole("region", { name: "Unplaced entities" }),
    ).toBeInTheDocument();

    await fireEvent.click(
      screen.getByRole("button", { name: "host-7, no segment" }),
    );

    expect(document.canvasSelection).toEqual({
      kind: "node",
      nodeId: PLACEMENT_ISSUE_ENTITY_ID,
    });
  });

  it("lists a pending entity while its draft projection is in flight", async () => {
    const { container, document } = renderCanvas();

    document.addNode(credentialNode("new-cred", 800, 600));
    await tick();

    await fireEvent.click(
      screen.getByRole("button", { name: "Unplaced entities (4)" }),
    );

    expect(
      container
        .querySelector("[data-unplaced-entity='new-cred']")
        ?.getAttribute("data-unplaced-status"),
    ).toBe("pending");
    expect(
      container
        .querySelector(`[data-unplaced-entity='${NO_PLACEMENT_ENTITY_ID}']`)
        ?.getAttribute("data-unplaced-status"),
    ).toBe("no_placement");
  });

  it("clears pins from the toolbar only when pins exist", async () => {
    const { document } = renderCanvas();

    expect(
      screen.queryByRole("button", { name: "Clear pins (1)" }),
    ).not.toBeInTheDocument();

    document.togglePin("web-1");
    await tick();

    await fireEvent.click(
      screen.getByRole("button", { name: "Clear pins (1)" }),
    );

    expect(document.pinnedEntityIds).toEqual([]);
  });

  it("keeps the selection empty for an unplaced entity the graph lacks", async () => {
    const { container, document } = renderCanvas();

    await fireEvent.click(
      screen.getByRole("button", { name: "Unplaced entities (3)" }),
    );

    const missing = container.querySelector(
      "[data-unplaced-selectable='false']",
    );
    expect(missing).not.toBeNull();

    await fireEvent.click(missing!);

    expect(document.canvasSelection).toEqual({ kind: "none" });
  });

  it("selects a pending relationship without inventing a node", async () => {
    const { container, document } = renderCanvas();

    document.createConnection(
      reachabilityEdge("pending-link", "segment-a", "segment-a"),
    );
    document.clearSelection();
    await tick();

    await fireEvent.click(
      screen.getByRole("button", { name: "Unplaced entities (4)" }),
    );

    const row = container.querySelector(
      "[data-unplaced-entity='pending-link']",
    )!;
    expect(row.getAttribute("data-unplaced-selectable")).toBe("true");

    await fireEvent.click(row);

    expect(document.canvasSelection).toEqual({
      kind: "edge",
      edgeId: "pending-link",
    });
  });
});
