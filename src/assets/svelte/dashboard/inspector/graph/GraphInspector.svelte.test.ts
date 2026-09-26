import type { GraphContract } from "../../../contracts.generated/graph";
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import GraphInspector from "./GraphInspector.svelte";
import {
  graphContract,
  hostNode,
  hostRecord,
  issueRecord,
  projectionOf,
  segmentNode,
  segmentRecord,
} from "../../graph/__tests__/topology-fixtures";
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

  it("shows document-level projection state and placement counts", async () => {
    const graph = graphContract([
      segmentNode("zone-1"),
      hostNode("host-1"),
      hostNode("orphan-1"),
    ]);
    const projection = projectionOf({
      segments: [segmentRecord("zone-1", ["host-1"])],
      hosts: [hostRecord("host-1", "zone-1")],
      issues: [issueRecord("host_without_segment", "orphan-1")],
    });
    const { container, rerender } = render(GraphInspector, {
      props: {
        graph,
        onTitleChange: vi.fn(),
        projection,
        projectionStatus: "pending" as const,
      },
    });

    const section = container.querySelector("[data-projection-status]")!;
    expect(section.getAttribute("data-projection-status")).toBe("pending");
    expect(screen.getByText("Updating")).toBeInTheDocument();
    expect(screen.getByText("Placement issues")).toBeInTheDocument();
    expect(screen.getByText("Unplaced")).toBeInTheDocument();

    await rerender({
      graph,
      onTitleChange: vi.fn(),
      projection,
      projectionStatus: "error" as const,
    });

    expect(
      container.querySelector("[data-projection-status='error']"),
    ).not.toBeNull();
    expect(
      screen.getByText("Stale · grouping unavailable"),
    ).toBeInTheDocument();
  });

  it("shows the draft flow state of a draft projection", () => {
    const graph = graphContract([segmentNode("zone-1"), hostNode("host-1")]);
    render(GraphInspector, {
      props: {
        graph,
        onTitleChange: vi.fn(),
        projection: projectionOf({
          segments: [segmentRecord("zone-1", ["host-1"])],
          hosts: [hostRecord("host-1", "zone-1")],
        }),
        projectionSource: "draft" as const,
      },
    });

    expect(screen.getByText("Ready · draft flows unsaved")).toBeInTheDocument();
  });

  it("hides every topology field without a projection", () => {
    const graph = graphContract([hostNode("host-1")]);
    const { container } = render(GraphInspector, {
      props: { graph, onTitleChange: vi.fn() },
    });

    expect(container.querySelector("[data-projection-status]")).toBeNull();
    expect(screen.queryByText("Topology")).toBeNull();
  });

  it("puts title errors with the title and graph errors in one summary", () => {
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
    render(GraphInspector, {
      props: {
        graph,
        onTitleChange: vi.fn(),
        errors: [
          {
            entity_kind: "graph",
            entity_id: null,
            field_path: [],
            message: "Graph is invalid",
          },
          {
            entity_kind: "graph",
            entity_id: null,
            field_path: ["title"],
            message: "Title is invalid",
          },
          {
            entity_kind: "graph",
            entity_id: null,
            field_path: ["title"],
            message: "Title must be unique",
          },
        ],
      },
    });
    const [graphErrors, titleErrors] = screen.getAllByRole("alert");
    expect(graphErrors).toHaveTextContent("Graph is invalid");
    expect(titleErrors).toHaveTextContent("Title is invalid");
    expect(titleErrors).toHaveTextContent("Title must be unique");
    expect(screen.getByRole("textbox", { name: "Title" })).toHaveAttribute(
      "aria-describedby",
      titleErrors.id,
    );
  });
});
