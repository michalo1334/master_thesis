import type { GraphContract } from "../../../contracts.generated/graph";
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import GraphInspector from "./GraphInspector.svelte";
afterEach(cleanup);

describe("GraphInspector", () => {
  it("sends a non-empty title change and restores an empty title", async () => {
    const onTitleChange = vi.fn();
    const graph: GraphContract = {
      id: "graph-1",
      title: "Topology",
      revision_id: "revision-1",
      parent_revision_id: null,
      revision_kind: "original",
      revision_number: 1,
      nodes: [],
      edges: [],
    };

    render(GraphInspector, { props: { graph, onTitleChange } });
    const title = screen.getByRole("textbox", { name: "Title" });

    expect(title).toHaveAttribute("maxlength", "255");
    await fireEvent.change(title, { target: { value: "Renamed topology" } });
    expect(onTitleChange).toHaveBeenCalledWith("Renamed topology");

    await fireEvent.change(title, { target: { value: "   " } });
    expect(onTitleChange).toHaveBeenCalledOnce();
    expect(title).toHaveValue("Topology");
  });

  it("opens a parent revision and leaves the root as plain text", async () => {
    const onOpenParent = vi.fn();
    const graph: GraphContract = {
      id: "graph-1",
      title: "Topology",
      revision_id: "revision-2",
      parent_revision_id: "revision-1",
      revision_kind: "edit",
      revision_number: 2,
      nodes: [],
      edges: [],
    };

    const { rerender } = render(GraphInspector, {
      props: {
        graph,
        parentTitle: "Original topology",
        onTitleChange: vi.fn(),
        onOpenParent,
      },
    });
    await fireEvent.click(
      screen.getByRole("button", { name: "Original topology" }),
    );
    expect(onOpenParent).toHaveBeenCalledOnce();

    await rerender({ graph: { ...graph, parent_revision_id: null } });
    expect(screen.getByText("Root revision")).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Root revision" }),
    ).not.toBeInTheDocument();
  });
});
