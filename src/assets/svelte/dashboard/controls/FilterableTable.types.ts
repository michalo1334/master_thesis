export interface FilterableTableColumn<Item> {
  key: string;
  header: string;
  getValue: (item: Item) => string;
  filterable?: boolean;
  align?: "start" | "end";
}
