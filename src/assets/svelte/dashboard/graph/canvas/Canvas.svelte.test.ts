import type { GraphContract } from "../../../contracts.generated/graph";
import { afterEach, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import Canvas from "./Canvas.svelte";
afterEach(cleanup);

const graph: GraphContract = {
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

it("clears canvas selection when blank space is clicked", async () => {
  const onSelectEdge = vi.fn();
  const onClearSelection = vi.fn();

  render(Canvas, {
    props: {
      graph,
      onSelectEdge,
      onClearSelection,
    },
  });

  await fireEvent.click(screen.getByRole("application"));

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
