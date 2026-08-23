import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import type { Component } from "svelte";
import DocumentOutline from "./DocumentOutline.svelte";
import { buildOutline, type OutlineGroup, type OutlineNode } from "./outline";

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

  it("renders item depth", () => {
    renderOutline();

    expect(row("Graph 1")).toHaveAttribute("data-depth", "1");
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
