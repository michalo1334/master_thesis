import { afterEach, describe, expect, it } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import FilterableTable from "./FilterableTable.svelte";
import type { FilterableTableColumn } from "./FilterableTable.svelte";

interface Item {
  id: string;
  title: string;
  description?: string;
  count: number;
  disabled?: boolean;
}

const TypedFilterableTable = FilterableTable as typeof FilterableTable<Item>;

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

  it("shows the empty message when items is empty", () => {
    render(TypedFilterableTable, {
      props: {
        items: [],
        columns,
        getKey: (i: Item) => i.id,
        emptyMessage: "Nothing here",
        noMatchMessage: "No match",
      },
    });

    expect(screen.getByText("Nothing here")).toBeInTheDocument();
  });

  it("shows the no-match message when filter yields zero", async () => {
    render(TypedFilterableTable, {
      props: {
        items,
        columns,
        getKey: (i: Item) => i.id,
        emptyMessage: "Nothing here",
        noMatchMessage: "No matches",
      },
    });

    const search = screen.getByRole("searchbox");
    await fireEvent.input(search, { target: { value: "nothingmatches" } });

    expect(screen.getByText("No matches")).toBeInTheDocument();
  });

  it("paginates rows when count exceeds perPage", () => {
    const manyItems: Item[] = Array.from({ length: 20 }, (_, i) => ({
      id: `item-${i}`,
      title: `Item ${i}`,
      description: `Desc ${i}`,
      count: i,
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

    expect(screen.getByText("Item 0")).toBeInTheDocument();
    expect(screen.queryByText("Item 9")).not.toBeInTheDocument();
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
