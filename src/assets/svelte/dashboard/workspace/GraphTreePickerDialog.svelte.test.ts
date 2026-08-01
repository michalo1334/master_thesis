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
  graph_id: "root",
  revision_id: "root-r1",
  title: "Root graph",
  node_count: 1,
  edge_count: 0,
  parent_revision_id: null,
  revision_kind: "original",
  revision_number: 1,
};

const child: GraphSummary = {
  graph_id: "child",
  revision_id: "child-r1",
  title: "Child graph",
  node_count: 2,
  edge_count: 1,
  parent_revision_id: root.revision_id,
  revision_kind: "edit",
  revision_number: 2,
};

const grandchild: GraphSummary = {
  graph_id: "grandchild",
  revision_id: "grandchild-r1",
  title: "Grandchild graph",
  node_count: 3,
  edge_count: 2,
  parent_revision_id: child.revision_id,
  revision_kind: "edit",
  revision_number: 3,
};

const sibling: GraphSummary = {
  graph_id: "sibling",
  revision_id: "sibling-r1",
  title: "Sibling graph",
  node_count: 1,
  edge_count: 0,
  parent_revision_id: null,
  revision_kind: "original",
  revision_number: 1,
};

const siblingChild: GraphSummary = {
  graph_id: "sibling-child",
  revision_id: "sibling-child-r1",
  title: "Sibling child graph",
  node_count: 1,
  edge_count: 0,
  parent_revision_id: sibling.revision_id,
  revision_kind: "edit",
  revision_number: 2,
};

afterEach(cleanup);

describe("GraphTreePickerDialog", () => {
  it("accepts a contextual title and description", () => {
    render(GraphTreePickerDialog, {
      props: {
        open: true,
        onOpenChange: vi.fn(),
        summaries: [root],
        onSelect: vi.fn(),
        title: "Compare graphs",
        description: "Select the base graph to compare.",
      },
    });

    expect(
      screen.getByRole("heading", { name: "Compare graphs" }),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Select the base graph to compare."),
    ).toBeInTheDocument();
  });

  it("marks the selected graph without adding a second selection affordance", async () => {
    const { rerender } = render(GraphTreePickerDialog, {
      props: {
        open: true,
        onOpenChange: vi.fn(),
        summaries: [root],
        onSelect: vi.fn(),
      },
    });

    await rerender({ selectedRevisionId: root.revision_id });

    const row = screen.getByRole("button", { name: root.title }).closest("tr");
    const indicator = row?.querySelector<HTMLInputElement>(
      'input[type="checkbox"]',
    );
    expect(row).toHaveAttribute("data-selected", "true");
    expect(indicator).toBeChecked();
    expect(indicator).toHaveAttribute("aria-hidden", "true");
    expect(screen.queryByRole("checkbox")).not.toBeInTheDocument();
  });

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
