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

afterEach(cleanup);

describe("GraphTreePickerDialog", () => {
  it("flattens child summaries and selects the child", async () => {
    const onSelect = vi.fn().mockResolvedValue(false);
    render(GraphTreePickerDialog, {
      props: {
        open: true,
        onOpenChange: vi.fn(),
        summaries: [root, child],
        onSelect,
      },
    });

    const rootButton = screen.getByRole("button", { name: /root graph/i });
    const childButton = screen.getByRole("button", { name: /child graph/i });
    expect(rootButton.closest("tr")).toHaveAttribute("data-depth", "0");
    expect(childButton.closest("tr")).toHaveAttribute("data-depth", "1");

    await fireEvent.click(childButton);
    await waitFor(() => expect(onSelect).toHaveBeenCalledWith(child));
  });
});
