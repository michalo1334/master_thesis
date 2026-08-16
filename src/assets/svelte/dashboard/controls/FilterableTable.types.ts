import type { Snippet } from "svelte";

export interface FilterableTableColumn<Item> {
  key: string;
  header: string | Snippet;
  getValue: (item: Item) => string;
  filterable?: boolean;
  align?: "start" | "end";
}
