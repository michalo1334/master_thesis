import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import GraphInspector from "./GraphInspector.svelte";
import type { LoadedGraph } from "../../contract";

afterEach(cleanup);

describe("GraphInspector", () => {
  it("sends a non-empty title change and restores an empty title", async () => {
    const onTitleChange = vi.fn();
    const graph: LoadedGraph = {
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
});
