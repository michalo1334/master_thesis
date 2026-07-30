import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import GraphTreePickerDialog from "./GraphTreePickerDialog.svelte";
import type { GraphSummary } from "../contract";

const root: GraphSummary = {
  id: "root",
  title: "Root graph",
  nodeCount: 1,
  edgeCount: 0,
  parentId: null,
  tags: [],
};

const child: GraphSummary = {
  id: "child",
  title: "Child graph",
  nodeCount: 2,
  edgeCount: 1,
  parentId: root.id,
  tags: [],
};

const grandchild: GraphSummary = {
  id: "grandchild",
  title: "Grandchild graph",
  nodeCount: 3,
  edgeCount: 2,
  parentId: child.id,
  tags: [],
};

const sibling: GraphSummary = {
  id: "sibling",
  title: "Sibling graph",
  nodeCount: 1,
  edgeCount: 0,
  parentId: null,
  tags: [],
};

const siblingChild: GraphSummary = {
  id: "sibling-child",
  title: "Sibling child graph",
  nodeCount: 1,
  edgeCount: 0,
  parentId: sibling.id,
  tags: [],
};

afterEach(cleanup);

describe("GraphTreePickerDialog", () => {
  it("shows roots initially and expands each branch independently", async () => {
    const onSelect = vi.fn().mockResolvedValue(false);
    render(GraphTreePickerDialog, {
      props: {
        open: true,
        onOpenChange: vi.fn(),
        summaries: [root, child, grandchild, sibling, siblingChild],
        onSelect,
      },
    });

    const rootButton = screen.getByRole("button", { name: "Root graph" });
    expect(rootButton.closest("tr")).toHaveAttribute("data-depth", "0");
    expect(
      screen.queryByRole("button", { name: "Child graph" }),
    ).not.toBeInTheDocument();

    const rootToggle = screen.getByRole("button", {
      name: "Expand Root graph",
    });
    expect(rootToggle).toHaveAttribute("aria-expanded", "false");
    await fireEvent.click(rootToggle);

    const childButton = screen.getByRole("button", { name: "Child graph" });
    expect(childButton.closest("tr")).toHaveAttribute("data-depth", "1");
    expect(
      screen.queryByRole("button", { name: "Grandchild graph" }),
    ).not.toBeInTheDocument();
    expect(rootToggle).toHaveAttribute("aria-expanded", "true");

    await fireEvent.click(
      screen.getByRole("button", { name: "Expand Child graph" }),
    );
    const grandchildButton = screen.getByRole("button", {
      name: "Grandchild graph",
    });
    expect(grandchildButton.closest("tr")).toHaveAttribute("data-depth", "2");

    await fireEvent.click(childButton);
    await waitFor(() => expect(onSelect).toHaveBeenCalledWith(child));

    await fireEvent.click(
      screen.getByRole("button", { name: "Expand Sibling graph" }),
    );
    expect(
      screen.getByRole("button", { name: "Sibling child graph" }),
    ).toBeInTheDocument();

    await fireEvent.click(rootToggle);
    expect(
      screen.queryByRole("button", { name: "Child graph" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Sibling child graph" }),
    ).toBeInTheDocument();
  });

  it("expands and collapses all branches", async () => {
    render(GraphTreePickerDialog, {
      props: {
        open: true,
        onOpenChange: vi.fn(),
        summaries: [root, child, grandchild],
        onSelect: vi.fn(),
      },
    });

    await fireEvent.click(screen.getByRole("button", { name: "Expand all" }));
    expect(
      screen.getByRole("button", { name: "Grandchild graph" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Collapse Root graph" }),
    ).toHaveAttribute("aria-expanded", "true");
    expect(
      screen.getByRole("button", { name: "Collapse Child graph" }),
    ).toHaveAttribute("aria-expanded", "true");

    await fireEvent.click(screen.getByRole("button", { name: "Collapse all" }));
    expect(
      screen.getByRole("button", { name: "Root graph" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Child graph" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Expand Root graph" }),
    ).toHaveAttribute("aria-expanded", "false");
  });

  it("resets to roots when reopened", async () => {
    const onOpenChange = vi.fn();
    const { rerender } = render(GraphTreePickerDialog, {
      props: {
        open: true,
        onOpenChange,
        summaries: [root, child, grandchild],
        onSelect: vi.fn(),
      },
    });

    await fireEvent.click(screen.getByRole("button", { name: "Expand all" }));
    expect(
      screen.getByRole("button", { name: "Grandchild graph" }),
    ).toBeInTheDocument();

    await fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
    await rerender({ open: false });
    await rerender({ open: true });

    expect(
      screen.getByRole("button", { name: "Root graph" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Child graph" }),
    ).not.toBeInTheDocument();
  });
});
