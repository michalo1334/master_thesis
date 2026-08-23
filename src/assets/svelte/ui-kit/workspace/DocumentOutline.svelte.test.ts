import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import type { Component } from "svelte";
import DocumentOutline from "./DocumentOutline.svelte";
import {
  buildOutline,
  type OutlineGroup,
  type OutlineNode,
  type OutlineRow,
} from "./outline";

type OutlineProps = {
  rows: ReturnType<typeof buildOutline<string, string>>;
  rowSnippet?: (
    row: ReturnType<typeof buildOutline<string, string>>[number],
  ) => unknown;
  selectedId?: string;
  onSelect: (id: string, event: MouseEvent) => void;
  collapsed: boolean;
  onCollapsedChange: (collapsed: boolean) => void;
  onDrop?: (drag: string, drop: string) => void;
  canDrop?: (drag: string, drop: string) => boolean;
};

const TypedDocumentOutline = DocumentOutline as Component<OutlineProps>;

const nodes: OutlineNode<string>[] = [
  {
    id: "graph-1",
    label: "Graph 1",
    icon: "share",
    kind: "graph",
    groupId: "folder-1",
    drag: { data: "graph-1" },
  },
];

const groups: OutlineGroup<string>[] = [
  {
    id: "folder-1",
    label: "Threat models",
    icon: "folder",
    depth: 1,
    drop: { data: "folder-1" },
  },
];

function renderOutline(
  overrides: Partial<{
    rows: ReturnType<typeof buildOutline<string, string>>;
    canDrop: (drag: string, drop: string) => boolean;
    selectedId: string;
    collapsed: boolean;
  }> = {},
) {
  const onDrop = vi.fn();
  const onSelect = vi.fn();
  const onCollapsedChange = vi.fn();
  const result = render(TypedDocumentOutline, {
    props: {
      rows: buildOutline(nodes, groups),
      collapsed: false,
      onSelect,
      onCollapsedChange,
      onDrop,
      ...overrides,
    },
  });
  return { onDrop, onSelect, onCollapsedChange, ...result };
}

function row(name: string): HTMLElement {
  return screen.getByRole("button", { name, hidden: true }).closest("li")!;
}

function header(name: string): HTMLElement {
  return screen.getByRole("heading", { name, hidden: true }).closest("li")!;
}

afterEach(cleanup);

describe("DocumentOutline", () => {
  it("makes a row draggable only when it declares a drag descriptor", () => {
    renderOutline();

    expect(row("Graph 1")).toHaveAttribute("draggable", "true");
  });

  it("calls onDrop with both application payloads on a compatible group", async () => {
    const { onDrop } = renderOutline();

    await fireEvent.dragStart(row("Graph 1"));
    await fireEvent.dragOver(header("Threat models"));
    expect(header("Threat models")).toHaveClass("drop-target");

    await fireEvent.drop(header("Threat models"));

    expect(onDrop).toHaveBeenCalledWith("graph-1", "folder-1");
  });

  it("rejects a target when canDrop returns false", async () => {
    const { onDrop } = renderOutline({ canDrop: () => false });

    await fireEvent.dragStart(row("Graph 1"));
    await fireEvent.dragOver(header("Threat models"));
    await fireEvent.drop(header("Threat models"));

    expect(header("Threat models")).not.toHaveClass("drop-target");
    expect(onDrop).not.toHaveBeenCalled();
  });

  it("selects a row on click and marks it current", async () => {
    const { onSelect } = renderOutline({ selectedId: "graph-1" });

    expect(row("Graph 1").querySelector("button")).toHaveAttribute(
      "aria-current",
      "page",
    );

    await fireEvent.click(
      screen.getByRole("button", { name: "Graph 1", hidden: true }),
    );
    expect(onSelect).toHaveBeenCalledWith("graph-1", expect.any(MouseEvent));
    expect(row("Graph 1").querySelector("button")).not.toHaveAttribute(
      "aria-pressed",
    );
  });

  it("marks a chosen row as pressed and forwards click modifiers", async () => {
    const onSelect = vi.fn();
    render(TypedDocumentOutline, {
      props: {
        rows: buildOutline([{ ...nodes[0], pressed: true }], groups),
        collapsed: false,
        onSelect,
        onCollapsedChange: vi.fn(),
      },
    });
    const button = screen.getByRole("button", {
      name: "Graph 1",
      hidden: true,
    });

    expect(button).toHaveAttribute("aria-pressed", "true");
    expect(button.querySelector(".hero-check")).toBeInTheDocument();

    await fireEvent.click(button, { ctrlKey: true });
    expect(onSelect).toHaveBeenCalledWith(
      "graph-1",
      expect.objectContaining({ ctrlKey: true }),
    );
  });

  it("renders one guide for each nested level", () => {
    const rows: OutlineRow<string, string>[] = [0, 1, 2].map((depth) => ({
      type: "item" as const,
      id: `graph-${depth}`,
      label: `Graph ${depth}`,
      icon: "share",
      kind: "graph",
      depth,
      hasChildren: false,
      guides: depth === 0 ? [] : depth === 1 ? ["tee"] : ["line", "elbow"],
    }));
    renderOutline({ rows });

    for (const depth of [0, 1, 2]) {
      const item = row(`Graph ${depth}`);
      expect(item).toHaveAttribute("data-depth", `${depth}`);
      expect(item.querySelectorAll(".document-outline-guide")).toHaveLength(
        depth,
      );
    }
    expect(row("Graph 0").querySelector(".document-outline-guides")).toBeNull();
    expect(
      row("Graph 1").querySelector(".document-outline-guide-tee"),
    ).toBeInTheDocument();
    expect(
      row("Graph 2").querySelectorAll(".document-outline-guide")[0],
    ).toHaveClass("document-outline-guide-line");
    expect(
      screen.getByRole("button", { name: "Graph 1", hidden: true }),
    ).toHaveAccessibleName("Graph 1");
  });

  it("builds sibling-aware connector paths", () => {
    const rows = buildOutline<string, string>(
      [
        { ...nodes[0], id: "root-a", label: "Root A", parentId: undefined },
        { ...nodes[0], id: "root-b", label: "Root B", parentId: undefined },
        { ...nodes[0], id: "child-a", label: "Child A", parentId: "root-a" },
        { ...nodes[0], id: "child-b", label: "Child B", parentId: "root-a" },
        {
          ...nodes[0],
          id: "grandchild-a",
          label: "Grandchild A",
          parentId: "child-a",
        },
        {
          ...nodes[0],
          id: "grandchild-b",
          label: "Grandchild B",
          parentId: "child-b",
        },
      ],
      [],
    );

    expect(rows.find((row) => row.id === "root-a")).toMatchObject({
      guides: [],
      hasChildren: true,
    });
    expect(rows.find((row) => row.id === "root-b")).toMatchObject({
      hasChildren: false,
    });
    expect(rows.find((row) => row.id === "child-a")).toMatchObject({
      guides: ["tee"],
    });
    expect(rows.find((row) => row.id === "child-b")).toMatchObject({
      guides: ["elbow"],
    });
    expect(rows.find((row) => row.id === "grandchild-a")).toMatchObject({
      guides: ["line", "elbow"],
    });
    expect(rows.find((row) => row.id === "grandchild-b")).toMatchObject({
      guides: ["space", "elbow"],
    });

    const groupedRows = buildOutline(nodes, groups);
    expect(groupedRows.find((row) => row.id === "graph-1")).toMatchObject({
      guides: ["elbow"],
    });
  });

  it("renders a connector container for parent rows", () => {
    const rows = buildOutline<string, string>(
      [
        { ...nodes[0], id: "parent", label: "Parent" },
        { ...nodes[0], id: "child", label: "Child", parentId: "parent" },
      ],
      [],
    );
    renderOutline({ rows });

    expect(row("Parent").querySelector(".document-outline-guides")).toHaveClass(
      "document-outline-guides-has-children",
    );
    expect(
      row("Parent").querySelector("[data-has-children]"),
    ).toBeInTheDocument();
    expect(
      row("Child").querySelector(".document-outline-guides"),
    ).toBeInTheDocument();
  });

  it("renders an empty group header as a drop target", async () => {
    const emptyGroup: OutlineGroup<string> = {
      id: "folder-empty",
      label: "Empty folder",
      icon: "folder",
      depth: 1,
      drop: { data: "folder-empty" },
    };
    const onDrop = vi.fn();
    const onSelect = vi.fn();
    const onCollapsedChange = vi.fn();
    render(TypedDocumentOutline, {
      props: {
        rows: buildOutline(nodes, [emptyGroup]),
        collapsed: false,
        onSelect,
        onCollapsedChange,
        onDrop,
      },
    });

    expect(header("Empty folder")).toBeInTheDocument();

    await fireEvent.dragStart(row("Graph 1"));
    await fireEvent.dragOver(header("Empty folder"));
    expect(header("Empty folder")).toHaveClass("drop-target");

    await fireEvent.drop(header("Empty folder"));
    expect(onDrop).toHaveBeenCalledWith("graph-1", "folder-empty");
  });

  it("requests a controlled expansion", async () => {
    const { onCollapsedChange } = renderOutline({ collapsed: true });

    const toggle = screen.getByRole("button", {
      name: "Expand document outline",
      hidden: true,
    });
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(
      screen.queryByRole("button", { name: "Graph 1", hidden: true }),
    ).not.toBeInTheDocument();

    await fireEvent.click(toggle);
    expect(onCollapsedChange).toHaveBeenCalledWith(false);
  });
});
