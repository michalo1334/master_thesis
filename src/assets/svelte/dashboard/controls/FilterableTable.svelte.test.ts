import { afterEach, describe, expect, it } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import type { Component } from "svelte";
import FilterableTable from "./FilterableTable.svelte";
import type { FilterableTableColumn } from "./FilterableTable.types";

interface Item {
  id: string;
  title: string;
  description?: string;
  count: number;
  disabled?: boolean;
}

const TypedFilterableTable = FilterableTable as unknown as Component<
  { items: Item[]; columns: FilterableTableColumn<Item>[] } & Record<
    string,
    unknown
  >
>;

const items: Item[] = [
  { id: "alpha", title: "Alpha", description: "First", count: 1 },
  { id: "beta", title: "Beta", description: "Second", count: 2 },
  {
    id: "gamma",
    title: "Gamma",
    description: "Third",
    count: 3,
    disabled: true,
  },
];

const columns: FilterableTableColumn<Item>[] = [
  {
    key: "title",
    header: "Name",
    getValue: (i: Item) => i.title,
    filterable: true,
  },
  {
    key: "description",
    header: "Description",
    getValue: (i: Item) => i.description ?? "",
    filterable: true,
  },
  {
    key: "count",
    header: "Count",
    getValue: (i: Item) => String(i.count),
    align: "end",
  },
];

afterEach(cleanup);

describe("FilterableTable", () => {
  it("renders all rows and column headers", () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    expect(
      screen.getByRole("columnheader", { name: "Name" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("columnheader", { name: "Description" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("columnheader", { name: "Count" }),
    ).toBeInTheDocument();

    for (const item of items) {
      expect(screen.getByText(item.title)).toBeInTheDocument();
    }
  });

  it("renders radio inputs in single selection mode", () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        selectionMode: "single",
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    expect(screen.getByRole("radio", { name: /alpha/i })).toBeInTheDocument();
    expect(screen.getByRole("radio", { name: /beta/i })).toBeInTheDocument();
  });

  it("renders checkbox inputs in multiple selection mode", () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        selectionMode: "multiple",
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    expect(
      screen.getByRole("checkbox", { name: /alpha/i }),
    ).toBeInTheDocument();
    expect(screen.getByRole("checkbox", { name: /beta/i })).toBeInTheDocument();
  });

  it("renders no selection column when mode is none", () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        selectionMode: "none",
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    expect(screen.queryByRole("radio")).not.toBeInTheDocument();
    expect(screen.queryByRole("checkbox")).not.toBeInTheDocument();
  });

  it("filters rows by search query across filterable columns only", async () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    const search = screen.getByRole("searchbox");
    await fireEvent.input(search, { target: { value: "second" } });

    expect(screen.getByText("Beta")).toBeInTheDocument();
    expect(screen.queryByText("Alpha")).not.toBeInTheDocument();
    expect(screen.queryByText("Gamma")).not.toBeInTheDocument();
  });

  it("does not match non-filterable columns", async () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns: [
          {
            key: "title",
            header: "Name",
            getValue: (i: Item) => i.title,
            filterable: true,
          },
          {
            key: "count",
            header: "Count",
            getValue: (i: Item) => String(i.count),
          },
        ] satisfies FilterableTableColumn<Item>[],
        getKey: (i: Item) => i.id,
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    const search = screen.getByRole("searchbox");
    await fireEvent.input(search, { target: { value: "2" } });

    expect(screen.queryByText("Alpha")).not.toBeInTheDocument();
    expect(screen.queryByText("Beta")).not.toBeInTheDocument();
    expect(screen.queryByText("Gamma")).not.toBeInTheDocument();
  });

  it("clearing the search restores all rows", async () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    const search = screen.getByRole("searchbox") as HTMLInputElement;
    await fireEvent.input(search, { target: { value: "alpha" } });
    expect(screen.queryByText("Beta")).not.toBeInTheDocument();

    await fireEvent.input(search, { target: { value: "" } });

    for (const item of items) {
      expect(screen.getByText(item.title)).toBeInTheDocument();
    }
  });

  it("retains the single-selection table footprint for empty items", () => {
    const { container } = render(TypedFilterableTable, {
      props: {
        items: [],
        columns,
        getKey: (i: Item) => i.id,
        perPage: 5,
        selectionMode: "single",
        emptyMessage: "Nothing here",
        noMatchMessage: "No match",
      },
    });

    expect(screen.getByRole("status")).toHaveTextContent("Nothing here");
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
    expect(container.querySelector("table")).toHaveAttribute(
      "aria-hidden",
      "true",
    );
    expect(container.querySelectorAll("thead th")).toHaveLength(
      columns.length + 1,
    );
    expect(container.querySelectorAll("tbody tr")).toHaveLength(5);
    expect(
      container.querySelectorAll('tbody tr[aria-hidden="true"]'),
    ).toHaveLength(5);
    expect(screen.queryByRole("radio")).not.toBeInTheDocument();
  });

  it("retains the multiple-selection table footprint for no matches", async () => {
    const { container } = render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        perPage: 4,
        selectionMode: "multiple",
        emptyMessage: "Nothing here",
        noMatchMessage: "No matches",
      },
    });

    const search = screen.getByRole("searchbox");
    await fireEvent.input(search, { target: { value: "nothingmatches" } });

    expect(screen.getByRole("status")).toHaveTextContent("No matches");
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
    expect(container.querySelector("table")).toHaveAttribute(
      "aria-hidden",
      "true",
    );
    expect(container.querySelectorAll("thead th")).toHaveLength(
      columns.length + 1,
    );
    expect(container.querySelectorAll("tbody tr")).toHaveLength(4);
    expect(
      container.querySelectorAll('tbody tr[aria-hidden="true"]'),
    ).toHaveLength(4);
    expect(screen.queryByRole("checkbox")).not.toBeInTheDocument();
  });

  it("shows the first page and navigates to the second page", async () => {
    const manyItems: Item[] = Array.from({ length: 10 }, (_, i) => ({
      id: `item-${i + 1}`,
      title: `Item ${i + 1}`,
      description: `Desc ${i + 1}`,
      count: i + 1,
    }));

    render(TypedFilterableTable, {
      props: {
        items: manyItems,
        columns,
        getKey: (i: Item) => i.id,
        perPage: 5,
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    for (let i = 1; i <= 5; i++) {
      expect(screen.getByText(`Item ${i}`)).toBeInTheDocument();
    }
    expect(screen.queryByText("Item 6")).not.toBeInTheDocument();

    await fireEvent.click(screen.getByRole("button", { name: "Page 2" }));

    for (let i = 6; i <= 10; i++) {
      expect(screen.getByText(`Item ${i}`)).toBeInTheDocument();
    }
    expect(screen.queryByText("Item 1")).not.toBeInTheDocument();
  });

  it("reserves per-page rows without exposing spacers to assistive technology", async () => {
    const { container } = render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        perPage: 5,
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    expect(container.querySelectorAll("tbody tr")).toHaveLength(5);
    expect(
      container.querySelectorAll('tbody tr[aria-hidden="true"]'),
    ).toHaveLength(2);
    expect(
      container.querySelectorAll(".filterable-table-spacer-control"),
    ).toHaveLength(0);
    expect(screen.getAllByRole("row")).toHaveLength(4);

    await fireEvent.input(screen.getByRole("searchbox"), {
      target: { value: "alpha" },
    });

    expect(container.querySelectorAll("tbody tr")).toHaveLength(5);
    expect(
      container.querySelectorAll('tbody tr[aria-hidden="true"]'),
    ).toHaveLength(4);
    expect(screen.getAllByRole("row")).toHaveLength(2);
  });

  it("uses hidden control-sized spacers in selection mode", () => {
    const { container } = render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        perPage: 5,
        selectionMode: "multiple",
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    const spacers = container.querySelectorAll('tbody tr[aria-hidden="true"]');
    expect(spacers).toHaveLength(2);
    for (const spacer of spacers) {
      const control = spacer.querySelector(".filterable-table-spacer-control");
      expect(control).toHaveAttribute("aria-hidden", "true");
      expect(control?.tagName).toBe("BUTTON");
      expect(control).toBeDisabled();
    }
    expect(screen.getAllByRole("checkbox")).toHaveLength(items.length);
    expect(screen.queryByRole("button")).not.toBeInTheDocument();
  });

  it("marks disabled items and disables their selection control", () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        selectionMode: "multiple",
        isDisabled: (i: Item) => i.disabled ?? false,
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    const gamma = screen.getByRole("checkbox", { name: /gamma/i });
    expect(gamma).toBeDisabled();
  });

  it("writes selected keys back through bind:selectedKeys", async () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        selectionMode: "multiple",
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    await fireEvent.click(screen.getByRole("checkbox", { name: /alpha/i }));
    await fireEvent.click(screen.getByRole("checkbox", { name: /beta/i }));

    expect(screen.getByRole("checkbox", { name: /alpha/i })).toBeChecked();
    expect(screen.getByRole("checkbox", { name: /beta/i })).toBeChecked();
  });

  it("seeds initial selection once on mount", () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        selectionMode: "multiple",
        initialSelectedKeys: ["alpha"],
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    expect(screen.getByRole("checkbox", { name: /alpha/i })).toBeChecked();
  });

  it("locks selection when the global disabled flag is set", () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        selectionMode: "multiple",
        disabled: true,
        emptyMessage: "Empty",
        noMatchMessage: "No match",
      },
    });

    const alpha = screen.getByRole("checkbox", { name: /alpha/i });
    expect(alpha).toBeDisabled();
  });
});
