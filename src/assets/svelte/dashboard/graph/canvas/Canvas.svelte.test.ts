import { afterAll, afterEach, beforeAll, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import Canvas from "./Canvas.svelte";
import type { LoadedGraph } from "../../contract";

afterEach(cleanup);

beforeAll(() => {
  vi.stubGlobal(
    "ResizeObserver",
    class {
      observe() {}
      unobserve() {}
      disconnect() {}
    },
  );
});

afterAll(() => vi.unstubAllGlobals());

const graph: LoadedGraph = {
  id: "graph",
  title: "Topology",
  nodes: [
    {
      id: "source",
      type: "Host",
      data: { name: "Source" },
      view_data: { x_pos: 0, y_pos: 0 },
    },
    {
      id: "target",
      type: "Host",
      data: { name: "Target" },
      view_data: { x_pos: 240, y_pos: 0 },
    },
  ],
  edges: [],
};

it("renders structural flows behind nodes and clears canvas selection on click", async () => {
  const onSelectEdge = vi.fn();
  const onClearSelection = vi.fn();

  render(Canvas, {
    props: {
      graph,
      onSelectEdge,
      onClearSelection,
      structuralFlows: [
        {
          id: "flow-1",
          sourceName: "Source",
          sourcePosition: { x: 0, y: 0 },
          targetPosition: { x: 240, y: 0 },
          serviceName: "https",
        },
      ],
    },
  });

  const flow = screen.getByRole("img", {
    name: "Operational flow from Source to https",
  });
  const node = screen.getAllByRole("button", { name: "Host" })[0];

  expect(window.getComputedStyle(flow).pointerEvents).toBe("none");
  expect(
    flow.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING,
  ).toBe(Node.DOCUMENT_POSITION_FOLLOWING);

  await fireEvent.click(flow);

  expect(onSelectEdge).not.toHaveBeenCalled();
  expect(onClearSelection).toHaveBeenCalledOnce();
});

it("offers MissionCapability in the editable node menu", async () => {
  render(Canvas, {
    props: {
      graph,
      onAddNode: vi.fn(),
    },
  });

  await fireEvent.contextMenu(screen.getByRole("application"));
  const add = screen.getByRole("menuitem", { name: "Add" });
  await fireEvent.pointerEnter(add);
  await fireEvent.keyDown(add, { key: "ArrowRight" });

  expect(
    await screen.findByRole("menuitem", { name: "MissionCapability" }),
  ).toBeInTheDocument();
});
