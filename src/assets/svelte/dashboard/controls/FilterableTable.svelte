<script module lang="ts">
  export interface FilterableTableColumn<Item> {
    key: string;
    header: string;
    getValue: (item: Item) => string;
    filterable?: boolean;
    align?: "start" | "end";
  }
</script>

<script lang="ts" generics="Item">
  import {
    createTable,
    getCoreRowModel,
    getFilteredRowModel,
    getPaginationRowModel,
  } from "@tanstack/table-core";
  import type {
    ColumnDef,
    RowSelectionState,
    Table,
    TableState,
  } from "@tanstack/table-core";
  import { Checkbox, Pagination, RadioGroup } from "bits-ui";
  import { untrack } from "svelte";

  interface Props {
    items: readonly Item[];
    columns: readonly FilterableTableColumn<Item>[];
    getKey: (item: Item) => string;
    selectionMode?: "single" | "multiple" | "none";
    selectedKeys?: string[];
    initialSelectedKeys?: readonly string[];
    isDisabled?: (item: Item) => boolean;
    perPage?: number;
    searchPlaceholder?: string;
    emptyMessage: string;
    noMatchMessage: string;
    disabled?: boolean;
  }

  let {
    items,
    columns,
    getKey,
    selectionMode = "none",
    selectedKeys = $bindable([]),
    initialSelectedKeys = [],
    isDisabled = undefined,
    perPage = 8,
    searchPlaceholder = "Search…",
    emptyMessage,
    noMatchMessage,
    disabled = false,
  }: Props = $props();

  let search = $state("");
  let pageIndex = $state(0);
  let rowSelection = $state<RowSelectionState>({});
  let initialSeeded = $state(false);
  let tableRev = $state(0);

  const tanstackColumns = $derived<ColumnDef<Item, string>[]>(
    columns.map((c) => ({
      id: c.key,
      accessorFn: (item: Item) => c.getValue(item),
      header: c.header,
      filterFn: c.filterable ? ("includesString" as const) : "auto",
      enableGlobalFilter: c.filterable ?? false,
    })),
  );

  const table: Table<Item> = createTable<Item>({
    get data() {
      return items as Item[];
    },
    get columns() {
      return tanstackColumns;
    },
    getCoreRowModel: getCoreRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    globalFilterFn: "includesString" as const,
    renderFallbackValue: null,
    get state() {
      return {
        get globalFilter() {
          return search;
        },
        get pagination() {
          return { pageIndex, pageSize: perPage };
        },
        get rowSelection() {
          return rowSelection;
        },
      };
    },
    onStateChange: (updater) => {
      const oldState = table.getState();
      const newState: TableState =
        typeof updater === "function" ? updater(oldState) : updater;
      untrack(() => {
        if (newState.globalFilter !== search) search = newState.globalFilter;
        if (newState.pagination.pageIndex !== pageIndex) {
          pageIndex = newState.pagination.pageIndex;
        }
        if (!rowSelectionEqual(newState.rowSelection, rowSelection)) {
          rowSelection = newState.rowSelection;
        }
        tableRev++;
      });
    },
    enableRowSelection: (row) =>
      selectionMode !== "none" && !disabled && !isDisabled?.(row.original),
    enableMultiRowSelection: selectionMode === "multiple",
    getRowId: (item: Item, index: number) => getKey(item) || String(index),
  });

  $effect(() => {
    const t = table;
    void tableRev;
    t.setOptions((prev) => ({
      ...prev,
      data: items as Item[],
      columns: tanstackColumns,
    }));
  });

  $effect(() => {
    if (initialSeeded) return;
    initialSeeded = true;
    if (initialSelectedKeys.length === 0) return;
    const initial: RowSelectionState = {};
    for (const item of items) {
      const key = getKey(item);
      if (initialSelectedKeys.includes(key) && !isDisabled?.(item)) {
        initial[key] = true;
      }
    }
    untrack(() => {
      rowSelection = initial;
      pageIndex = 0;
      tableRev++;
    });
  });

  $effect(() => {
    if (selectionMode === "none") return;
    const keys = Object.keys(rowSelection).filter((k) => rowSelection[k]);
    const normalized =
      selectionMode === "single"
        ? keys.length > 0
          ? [keys[keys.length - 1]]
          : []
        : keys;
    if (
      selectedKeys.length === normalized.length &&
      selectedKeys.every((k, i) => k === normalized[i])
    ) {
      return;
    }
    selectedKeys = normalized;
  });

  $effect(() => {
    if (selectionMode === "none") return;
    const record: RowSelectionState = {};
    for (const k of selectedKeys) record[k] = true;
    if (!rowSelectionEqual(rowSelection, record)) {
      untrack(() => {
        rowSelection = record;
        tableRev++;
      });
    }
  });

  const filteredCount = $derived.by(() => {
    void tableRev;
    return table.getFilteredRowModel().rows.length;
  });
  const totalCount = $derived(items.length);
  const showPagination = $derived(filteredCount > perPage);

  const visibleRows = $derived.by(() => {
    void tableRev;
    return table.getRowModel().rows;
  });

  function setSingleKey(key: string): void {
    const record: RowSelectionState = key ? { [key]: true } : {};
    untrack(() => {
      rowSelection = record;
      tableRev++;
    });
  }

  function setMultiKeys(keys: string[]): void {
    const record: RowSelectionState = {};
    for (const k of keys) record[k] = true;
    untrack(() => {
      rowSelection = record;
      tableRev++;
    });
  }

  function rowSelectionEqual(
    a: RowSelectionState,
    b: RowSelectionState,
  ): boolean {
    const aKeys = Object.keys(a);
    const bKeys = Object.keys(b);
    if (aKeys.length !== bKeys.length) return false;
    return aKeys.every((k) => a[k] === b[k]);
  }
</script>

<div
  class="filterable-table"
  data-selection={selectionMode}
  data-disabled={disabled || undefined}
>
  <div class="filterable-table-toolbar">
    <input
      class="filterable-table-search"
      type="search"
      placeholder={searchPlaceholder}
      bind:value={search}
      aria-label="Search"
      {disabled}
    />
    <span class="filterable-table-count">
      {filteredCount} of {totalCount}
    </span>
  </div>

  <div class="filterable-table-scroll">
    {#if totalCount === 0}
      <p class="filterable-table-message">{emptyMessage}</p>
    {:else if filteredCount === 0}
      <p class="filterable-table-message">{noMatchMessage}</p>
    {:else if selectionMode === "single"}
      <RadioGroup.Root
        class="filterable-table-root"
        value={Object.keys(rowSelection).find((k) => rowSelection[k]) ?? ""}
        onValueChange={setSingleKey}
      >
        <table class="filterable-table-table">
          <thead>
            <tr>
              <th class="filterable-table-select" aria-label="Select"></th>
              {#each columns as col (col.key)}
                <th class:filterable-table-align-end={col.align === "end"}>
                  {col.header}
                </th>
              {/each}
            </tr>
          </thead>
          <tbody>
            {#each visibleRows as row (row.id)}
              {@const rowDisabled = isDisabled?.(row.original) ?? false}
              <tr
                data-selected={row.getIsSelected() || undefined}
                data-disabled={rowDisabled || undefined}
              >
                <td class="filterable-table-select">
                  <RadioGroup.Item
                    class="filterable-table-control"
                    value={row.id}
                    disabled={rowDisabled || disabled}
                    aria-label={`Select ${row.id}`}
                  >
                    <span class="filterable-table-radio" aria-hidden="true"
                    ></span>
                  </RadioGroup.Item>
                </td>
                {#each columns as col (col.key)}
                  <td class:filterable-table-align-end={col.align === "end"}>
                    {row.getValue<string>(col.key)}
                  </td>
                {/each}
              </tr>
            {/each}
          </tbody>
        </table>
      </RadioGroup.Root>
    {:else if selectionMode === "multiple"}
      <Checkbox.Group
        class="filterable-table-root"
        value={Object.keys(rowSelection).filter((k) => rowSelection[k])}
        onValueChange={setMultiKeys}
      >
        <table class="filterable-table-table">
          <thead>
            <tr>
              <th class="filterable-table-select" aria-label="Select"></th>
              {#each columns as col (col.key)}
                <th class:filterable-table-align-end={col.align === "end"}>
                  {col.header}
                </th>
              {/each}
            </tr>
          </thead>
          <tbody>
            {#each visibleRows as row (row.id)}
              {@const rowDisabled = isDisabled?.(row.original) ?? false}
              <tr
                data-selected={row.getIsSelected() || undefined}
                data-disabled={rowDisabled || undefined}
              >
                <td class="filterable-table-select">
                  <Checkbox.Root
                    class="filterable-table-control"
                    value={row.id}
                    disabled={rowDisabled || disabled}
                    aria-label={`Select ${row.id}`}
                  >
                    <span class="filterable-table-checkbox" aria-hidden="true"
                    ></span>
                  </Checkbox.Root>
                </td>
                {#each columns as col (col.key)}
                  <td class:filterable-table-align-end={col.align === "end"}>
                    {row.getValue<string>(col.key)}
                  </td>
                {/each}
              </tr>
            {/each}
          </tbody>
        </table>
      </Checkbox.Group>
    {:else}
      <table class="filterable-table-table">
        <thead>
          <tr>
            {#each columns as col (col.key)}
              <th class:filterable-table-align-end={col.align === "end"}>
                {col.header}
              </th>
            {/each}
          </tr>
        </thead>
        <tbody>
          {#each visibleRows as row (row.id)}
            {@const rowDisabled = isDisabled?.(row.original) ?? false}
            <tr data-disabled={rowDisabled || undefined}>
              {#each columns as col (col.key)}
                <td class:filterable-table-align-end={col.align === "end"}>
                  {row.getValue<string>(col.key)}
                </td>
              {/each}
            </tr>
          {/each}
        </tbody>
      </table>
    {/if}
  </div>

  {#if showPagination}
    <div class="filterable-table-pagination">
      <Pagination.Root count={filteredCount} {perPage} bind:page={pageIndex}>
        {#snippet children({ pages, currentPage })}
          <Pagination.PrevButton class="filterable-table-page-button">
            ‹
          </Pagination.PrevButton>
          {#each pages as page (page.key)}
            {#if page.type === "ellipsis"}
              <span class="filterable-table-ellipsis">…</span>
            {:else}
              <Pagination.Page
                class={[
                  "filterable-table-page-button",
                  page.value === currentPage && "filterable-table-page-current",
                ]}
                {page}
              >
                {page.value}
              </Pagination.Page>
            {/if}
          {/each}
          <Pagination.NextButton class="filterable-table-page-button">
            ›
          </Pagination.NextButton>
        {/snippet}
      </Pagination.Root>
    </div>
  {/if}
</div>

<style>
  .filterable-table {
    display: grid;
    grid-template-rows: auto minmax(0, 1fr) auto;
    gap: var(--ds-space-2);
    min-width: 0;
  }

  .filterable-table-toolbar {
    display: flex;
    align-items: center;
    gap: var(--ds-space-3);
  }

  .filterable-table-search {
    flex: 1 1 auto;
    min-width: 0;
    min-height: var(--ds-control-height);
    padding: 0.1875rem 0.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    color: var(--ds-color-text);
    font-size: var(--ds-text-sm);
  }

  .filterable-table-search:not(:disabled):hover {
    border-color: var(--ds-color-accent);
  }

  .filterable-table-search:focus-visible {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 2px;
  }

  .filterable-table-search:disabled {
    color: var(--ds-color-text-faint);
    background: var(--ds-color-surface);
    cursor: default;
  }

  .filterable-table-count {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .filterable-table-scroll {
    min-height: 0;
    overflow: auto;
    border: 1px solid var(--ds-color-border-soft);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
  }

  .filterable-table-message {
    margin: 0;
    padding: var(--ds-space-4);
    color: var(--ds-color-text-secondary);
    text-align: center;
  }

  .filterable-table-table {
    width: 100%;
    border-collapse: collapse;
    font-size: var(--ds-text-sm);
  }

  .filterable-table-table thead th {
    position: sticky;
    top: 0;
    z-index: 1;
    padding: var(--ds-space-2) var(--ds-space-3);
    border-bottom: 1px solid var(--ds-color-border);
    background: var(--ds-color-surface);
    color: var(--ds-color-text-secondary);
    font-weight: 600;
    text-align: start;
    white-space: nowrap;
  }

  .filterable-table-table tbody td {
    padding: var(--ds-space-2) var(--ds-space-3);
    border-bottom: 1px solid var(--ds-color-border-soft);
    color: var(--ds-color-text);
    vertical-align: middle;
  }

  .filterable-table-table tbody tr:last-child td {
    border-bottom: 0;
  }

  .filterable-table-table tbody tr[data-selected] {
    background: var(--ds-color-accent-soft);
  }

  .filterable-table-table tbody tr[data-disabled] {
    color: var(--ds-color-text-faint);
  }

  :global(
    .filterable-table-table tbody tr[data-disabled] .filterable-table-control
  ) {
    cursor: not-allowed;
  }

  .filterable-table-align-end {
    text-align: end;
    font-variant-numeric: tabular-nums;
  }

  .filterable-table-select {
    width: 1px;
    white-space: nowrap;
  }

  :global(.filterable-table-control) {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 1.125rem;
    height: 1.125rem;
    border: 1px solid var(--ds-color-border);
    background: var(--ds-color-paper);
    cursor: pointer;
  }

  :global(.filterable-table-control:disabled) {
    cursor: not-allowed;
  }

  :global(.filterable-table-control[data-radio-group-item]) {
    border-radius: 50%;
  }

  :global(.filterable-table-control[data-checkbox-root]) {
    border-radius: var(--ds-radius-sm);
  }

  :global(.filterable-table-control[data-state="checked"]) {
    border-color: var(--ds-color-accent);
    background: var(--ds-color-accent);
  }

  :global(
    .filterable-table-control[data-radio-group-item][data-state="checked"]
  ) {
    box-shadow: inset 0 0 0 0.25rem var(--ds-color-paper);
  }

  :global(.filterable-table-control[data-checkbox-root][data-state="checked"]) {
    box-shadow: inset 0 0 0 0.25rem var(--ds-color-accent);
  }

  :global(.filterable-table-control:focus-visible) {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 2px;
  }

  .filterable-table-pagination {
    display: flex;
    justify-content: center;
    gap: var(--ds-space-1);
  }

  :global(.filterable-table-page-button) {
    min-width: 1.75rem;
    min-height: 1.75rem;
    padding: 0 0.375rem;
    border: 1px solid var(--ds-color-border-soft);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-paper);
    color: var(--ds-color-text);
    font-size: var(--ds-text-sm);
    cursor: pointer;
  }

  :global(.filterable-table-page-button:hover:not(:disabled)) {
    border-color: var(--ds-color-accent);
  }

  :global(.filterable-table-page-button:disabled) {
    color: var(--ds-color-text-faint);
    cursor: default;
  }

  :global(.filterable-table-page-current) {
    border-color: var(--ds-color-accent);
    background: var(--ds-color-accent);
    color: var(--ds-color-paper);
  }

  .filterable-table-ellipsis {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 1.75rem;
    min-height: 1.75rem;
    color: var(--ds-color-text-faint);
  }
</style>
