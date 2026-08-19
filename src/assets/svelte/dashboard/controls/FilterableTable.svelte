<script lang="ts" generics="Item">
  import {
    createTable,
    getCoreRowModel,
    getFilteredRowModel,
    getPaginationRowModel,
  } from "@tanstack/table-core";
  import type {
    ColumnDef,
    FilterFnOption,
    RowSelectionState,
    Table,
    TableState,
  } from "@tanstack/table-core";
  import { Checkbox, Pagination, RadioGroup } from "bits-ui";
  import { untrack } from "svelte";
  import type {
    FilterableTableColumn,
    FilterableTableServer,
  } from "./FilterableTable.types";

  interface Props {
    items: readonly Item[];
    columns: readonly FilterableTableColumn<Item>[];
    getKey: (item: Item) => string;
    selectionMode?: "single" | "multiple" | "none";
    selectedKeys?: string[];
    isDisabled?: (item: Item) => boolean;
    perPage?: number | "adaptive";
    searchPlaceholder?: string;
    emptyMessage: string;
    noMatchMessage: string;
    disabled?: boolean;
    server?: FilterableTableServer;
  }

  let {
    items,
    columns,
    getKey,
    selectionMode = "none",
    selectedKeys = $bindable([]),
    isDisabled = undefined,
    perPage = 8,
    searchPlaceholder = "Search…",
    emptyMessage,
    noMatchMessage,
    disabled = false,
    server = undefined,
  }: Props = $props();

  let search = $state("");
  let pageIndex = $state(0);
  let tableRev = $state(0);
  let scrollAreaHeight = $state(0);
  let headerHeight = $state(0);
  let reportedServerPerPage: number | undefined;
  const rowHeight = 40;

  const effectivePerPage = $derived(
    effectivePageSize(scrollAreaHeight, headerHeight),
  );

  const selectableKeys = $derived.by(
    () =>
      new Set(
        items.filter((item) => !isDisabled?.(item)).map((item) => getKey(item)),
      ),
  );
  const rowSelection = $derived.by<RowSelectionState>(() => {
    if (selectionMode === "none") return {};

    const keys = selectedKeys.filter((key) => selectableKeys.has(key));
    const selected = selectionMode === "single" ? keys.slice(-1) : keys;

    return Object.fromEntries(selected.map((key) => [key, true]));
  });
  const singleSelectedKey = $derived(
    Object.keys(rowSelection).find((key) => rowSelection[key]) ?? "",
  );
  const multipleSelectedKeys = $derived(
    Object.keys(rowSelection).filter((key) => rowSelection[key]),
  );
  const filteredCount = $derived.by(() => {
    if (server) return server.totalCount;

    const query = search.toLowerCase();
    if (!query) return items.length;

    return items.filter((item) =>
      columns.some(
        (column) =>
          column.filterable &&
          column.getValue(item).toLowerCase().includes(query),
      ),
    ).length;
  });
  const lastPageIndex = $derived(
    Math.max(0, Math.ceil(filteredCount / effectivePerPage) - 1),
  );
  const clampedPageIndex = $derived(
    Math.min(Math.max(server ? server.page - 1 : pageIndex, 0), lastPageIndex),
  );

  const tanstackColumns = $derived<ColumnDef<Item, string>[]>(
    columns.map((c) => ({
      id: c.key,
      accessorFn: (item: Item) => c.getValue(item),
      header: c.header,
      filterFn: (c.filterable
        ? "includesString"
        : "auto") as FilterFnOption<Item>,
      enableGlobalFilter: c.filterable ?? false,
    })),
  );

  const table = $derived.by<Table<Item>>(() =>
    createTable<Item>({
      get data() {
        return items as Item[];
      },
      get columns() {
        return tanstackColumns;
      },
      getCoreRowModel: getCoreRowModel(),
      ...(!server && {
        getFilteredRowModel: getFilteredRowModel(),
        getPaginationRowModel: getPaginationRowModel(),
      }),
      globalFilterFn: "includesString" as const,
      renderFallbackValue: null,
      get state() {
        return {
          get globalFilter() {
            return search;
          },
          get pagination() {
            return { pageIndex: clampedPageIndex, pageSize: effectivePerPage };
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
          if (newState.pagination.pageIndex !== clampedPageIndex) {
            pageIndex = newState.pagination.pageIndex;
          }
          tableRev++;
        });
      },
      enableRowSelection: (row) =>
        selectionMode !== "none" && !disabled && !isDisabled?.(row.original),
      get enableMultiRowSelection() {
        return selectionMode === "multiple";
      },
      getRowId: (item: Item, index: number) => getKey(item) || String(index),
    }),
  );

  const totalCount = $derived(server?.totalCount ?? items.length);
  const visibleCount = $derived(server ? items.length : filteredCount);
  const hasStatus = $derived(totalCount === 0 || filteredCount === 0);
  const showPagination = $derived(filteredCount > effectivePerPage);

  const visibleRows = $derived.by(() => {
    void tableRev;
    void clampedPageIndex;
    void effectivePerPage;
    return server ? table.getCoreRowModel().rows : table.getRowModel().rows;
  });

  function effectivePageSize(scrollHeight: number, headHeight: number): number {
    return perPage === "adaptive"
      ? scrollHeight > headHeight
        ? Math.max(1, Math.floor((scrollHeight - headHeight) / rowHeight))
        : 8
      : perPage;
  }

  function setScrollAreaHeight(height: number): void {
    scrollAreaHeight = height;
    reportServerPerPageSize();
  }

  function setHeaderHeight(height: number): void {
    headerHeight = height;
    reportServerPerPageSize();
  }

  function reportServerPerPageSize(): void {
    const nextPerPage = effectivePageSize(scrollAreaHeight, headerHeight);
    if (!server || perPage !== "adaptive") {
      reportedServerPerPage = undefined;
    } else if (
      reportedServerPerPage !== undefined &&
      reportedServerPerPage !== nextPerPage
    ) {
      server.onchange({
        search,
        page: clampedPageIndex + 1,
        perPage: nextPerPage,
      });
    }
    reportedServerPerPage = nextPerPage;
  }

  function setSingleKey(key: string): void {
    if (disabled || selectionMode !== "single") return;
    if (!key) {
      selectedKeys = [];
    } else if (selectableKeys.has(key)) {
      selectedKeys = [key];
    }
  }

  function setMultiKeys(keys: string[]): void {
    if (disabled || selectionMode !== "multiple") return;
    const visibleKeys = [...new Set(keys)].filter((key) =>
      selectableKeys.has(key),
    );
    selectedKeys = server
      ? [
          ...selectedKeys.filter((key) => !selectableKeys.has(key)),
          ...visibleKeys,
        ]
      : visibleKeys;
  }

  function setSearch(value: string): void {
    search = value;
    if (server) {
      server.onchange({ search, page: 1, perPage: effectivePerPage });
    } else {
      pageIndex = 0;
    }
  }

  function setPage(page: number): void {
    if (server) {
      server.onchange({ search, page, perPage: effectivePerPage });
    } else {
      pageIndex = page - 1;
    }
  }
</script>

<div
  class="filterable-table"
  data-selection={selectionMode}
  data-disabled={disabled || undefined}
  data-adaptive={perPage === "adaptive" || undefined}
  style:--filterable-table-row-height={`${rowHeight}px`}
>
  <div class="filterable-table-toolbar">
    <input
      class="filterable-table-search"
      type="search"
      placeholder={searchPlaceholder}
      bind:value={() => search, setSearch}
      aria-label="Search"
      {disabled}
    />
    <span class="filterable-table-count">
      {visibleCount} of {totalCount}
    </span>
  </div>

  {#snippet spacerRows(columnCount: number)}
    {#each { length: Math.max(0, effectivePerPage - visibleRows.length) }}
      <tr aria-hidden="true">
        {#if selectionMode !== "none"}
          <td class="filterable-table-select">
            <button
              type="button"
              class="filterable-table-control filterable-table-spacer-control"
              disabled
              aria-hidden="true"
            ></button>
          </td>
          <td colspan={columnCount - 1}>&nbsp;</td>
        {:else}
          <td colspan={columnCount}>&nbsp;</td>
        {/if}
      </tr>
    {/each}
  {/snippet}

  {#snippet headers()}
    {#each columns as col (col.key)}
      <th class:filterable-table-align-end={col.align === "end"}>
        {#if typeof col.header === "string"}
          {col.header}
        {:else}
          {@render col.header()}
        {/if}
      </th>
    {/each}
  {/snippet}

  <div
    class="filterable-table-scroll"
    bind:clientHeight={null, setScrollAreaHeight}
  >
    {#if hasStatus}
      <p class="filterable-table-message" role="status">
        {totalCount === 0 ? emptyMessage : noMatchMessage}
      </p>
    {/if}

    {#if selectionMode === "single"}
      <RadioGroup.Root
        class="filterable-table-root"
        value={singleSelectedKey}
        onValueChange={setSingleKey}
      >
        <table class="filterable-table-table">
          <thead bind:clientHeight={null, setHeaderHeight}>
            <tr>
              <th class="filterable-table-select" aria-label="Select"></th>
              {@render headers()}
            </tr>
          </thead>
          <tbody>
            {#if !hasStatus}
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
            {/if}
            {@render spacerRows(columns.length + 1)}
          </tbody>
        </table>
      </RadioGroup.Root>
    {:else if selectionMode === "multiple"}
      <Checkbox.Group
        class="filterable-table-root"
        value={multipleSelectedKeys}
        onValueChange={setMultiKeys}
      >
        <table class="filterable-table-table">
          <thead bind:clientHeight={null, setHeaderHeight}>
            <tr>
              <th class="filterable-table-select" aria-label="Select"></th>
              {@render headers()}
            </tr>
          </thead>
          <tbody>
            {#if !hasStatus}
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
            {/if}
            {@render spacerRows(columns.length + 1)}
          </tbody>
        </table>
      </Checkbox.Group>
    {:else}
      <table class="filterable-table-table">
        <thead bind:clientHeight={null, setHeaderHeight}>
          <tr>
            {@render headers()}
          </tr>
        </thead>
        <tbody>
          {#if !hasStatus}
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
          {/if}
          {@render spacerRows(columns.length)}
        </tbody>
      </table>
    {/if}
  </div>

  {#if showPagination}
    <div class="filterable-table-pagination">
      <Pagination.Root
        count={filteredCount}
        perPage={effectivePerPage}
        bind:page={() => clampedPageIndex + 1, setPage}
      >
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
    gap: var(--ui-space-2);
    min-width: 0;
  }

  .filterable-table-toolbar {
    display: flex;
    align-items: center;
    gap: var(--ui-space-3);
  }

  .filterable-table-search {
    flex: 1 1 auto;
    min-width: 0;
    min-height: var(--ui-control-height);
    padding: 0.1875rem 0.5rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    color: var(--ui-color-text);
    font-size: var(--ui-text-sm);
  }

  .filterable-table-search:not(:disabled):hover {
    border-color: var(--ui-color-accent);
  }

  .filterable-table-search:focus-visible {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: 2px;
  }

  .filterable-table-search:disabled {
    color: var(--ui-color-text-faint);
    background: var(--ui-color-surface);
    cursor: default;
  }

  .filterable-table-count {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .filterable-table-scroll {
    position: relative;
    min-height: 0;
    overflow: auto;
    border: 1px solid var(--ui-color-border-soft);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }

  .filterable-table[data-adaptive] {
    height: 100%;
  }

  .filterable-table-message {
    position: absolute;
    z-index: 2;
    inset: 0;
    display: grid;
    place-items: center;
    margin: 0;
    padding: var(--ui-space-4);
    color: var(--ui-color-text-secondary);
    text-align: center;
    pointer-events: none;
  }

  .filterable-table-table {
    width: 100%;
    border-collapse: collapse;
    font-size: var(--ui-text-sm);
  }

  .filterable-table-table thead th {
    position: sticky;
    top: 0;
    z-index: 1;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border);
    background: var(--ui-color-surface);
    color: var(--ui-color-text-secondary);
    font-weight: 600;
    text-align: start;
    white-space: nowrap;
  }

  .filterable-table-table tbody td {
    padding: var(--ui-space-2) var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border-soft);
    color: var(--ui-color-text);
    vertical-align: middle;
  }

  .filterable-table[data-adaptive] .filterable-table-table tbody tr {
    height: var(--filterable-table-row-height);
  }

  .filterable-table-table tbody tr:last-child td {
    border-bottom: 0;
  }

  .filterable-table-table tbody tr[data-selected] {
    background: var(--ui-color-accent-soft);
  }

  .filterable-table-table tbody tr[data-disabled] {
    color: var(--ui-color-text-faint);
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
    border: 1px solid var(--ui-color-border);
    background: var(--ui-color-paper);
    cursor: pointer;
  }

  :global(.filterable-table-control:disabled) {
    cursor: not-allowed;
  }

  :global(.filterable-table-control[data-radio-group-item]) {
    border-radius: 50%;
  }

  :global(.filterable-table-control[data-checkbox-root]) {
    border-radius: var(--ui-radius-sm);
  }

  :global(.filterable-table-control[data-state="checked"]) {
    border-color: var(--ui-color-accent);
    background: var(--ui-color-accent);
  }

  :global(
    .filterable-table-control[data-radio-group-item][data-state="checked"]
  ) {
    box-shadow: inset 0 0 0 0.25rem var(--ui-color-paper);
  }

  .filterable-table-checkbox {
    display: block;
    width: 0.375rem;
    height: 0.625rem;
    border-right: 2px solid transparent;
    border-bottom: 2px solid transparent;
    transform: rotate(45deg) translate(-1px, -1px);
    transition: border-color 0.1s;
  }

  :global(.filterable-table-control[data-checkbox-root][data-state="checked"])
    .filterable-table-checkbox {
    border-color: var(--ui-color-paper);
  }

  :global(.filterable-table-control:focus-visible) {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: 2px;
  }

  .filterable-table-spacer-control {
    visibility: hidden;
  }

  .filterable-table-pagination {
    display: flex;
    justify-content: center;
    gap: var(--ui-space-1);
  }

  :global(.filterable-table-page-button) {
    min-width: 1.75rem;
    min-height: 1.75rem;
    padding: 0 0.375rem;
    border: 1px solid var(--ui-color-border-soft);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-paper);
    color: var(--ui-color-text);
    font-size: var(--ui-text-sm);
    cursor: pointer;
  }

  :global(.filterable-table-page-button:hover:not(:disabled)) {
    border-color: var(--ui-color-accent);
  }

  :global(.filterable-table-page-button:disabled) {
    color: var(--ui-color-text-faint);
    cursor: default;
  }

  :global(.filterable-table-page-current) {
    border-color: var(--ui-color-accent);
    background: var(--ui-color-accent);
    color: var(--ui-color-paper);
  }

  .filterable-table-ellipsis {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 1.75rem;
    min-height: 1.75rem;
    color: var(--ui-color-text-faint);
  }
</style>
