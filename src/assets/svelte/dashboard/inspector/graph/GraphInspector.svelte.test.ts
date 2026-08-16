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

  it("opens a parent revision and leaves the root as plain text", async () => {
    const onOpenParent = vi.fn();
    const graph: LoadedGraph = {
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

  it("shows assigned analysis titles and saves multiple selections", async () => {
    const onAnalysesChange = vi.fn().mockResolvedValue(true);
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

    render(GraphInspector, {
      props: {
        graph,
        onTitleChange: vi.fn(),
        analyses: [
          { id: "analysis-1", title: "Baseline" },
          { id: "analysis-2", title: "Hardening" },
        ],
        analysisIds: ["analysis-1", "analysis-2"],
        onAnalysesChange,
      },
    });

    expect(screen.getByText("Baseline")).toBeInTheDocument();
    expect(screen.getByText("Hardening")).toBeInTheDocument();
    await fireEvent.click(
      screen.getByRole("button", { name: "Change analyses" }),
    );
    await fireEvent.click(screen.getByRole("button", { name: "Select (2)" }));

    expect(onAnalysesChange).toHaveBeenCalledWith(["analysis-1", "analysis-2"]);
  });
});
