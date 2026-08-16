import type { Snippet } from "svelte";

export interface FilterableTableServerQuery {
  search: string;
  page: number;
  perPage: number;
}

export interface FilterableTableServer {
  totalCount: number;
  page: number;
  onchange: (query: FilterableTableServerQuery) => void;
}

export interface FilterableTableColumn<Item> {
  key: string;
  header: string | Snippet;
  getValue: (item: Item) => string;
  filterable?: boolean;
  align?: "start" | "end";
}
