<script lang="ts">
  import type {
    DocumentCatalogItem,
    FetchDocumentCatalogReply,
  } from "../../contracts.generated/dashboard/workspace";
  import { onMount } from "svelte";
  import type { DashboardApi, DocumentCatalogQuery } from "../dashboard-api";
  import FilterableTable from "../../ui-kit/composites/FilterableTable.svelte";
  import type {
    FilterableTableColumn,
    FilterableTableServerQuery,
  } from "../../ui-kit/composites/FilterableTable.types";
  import MultiSelectFilter from "../../ui-kit/composites/MultiSelectFilter.svelte";
  import type { MultiSelectFilterOption } from "../../ui-kit/composites/MultiSelectFilter.svelte";
  import { DocumentCatalogDocument } from "./DocumentCatalogDocument.svelte";

  interface Props {
    document: DocumentCatalogDocument;
    api: DashboardApi;
  }

  let { document, api }: Props = $props();
  let items = $state.raw<DocumentCatalogItem[]>([]);
  let totalCount = $state(0);
  let filterOptions = $state.raw<FetchDocumentCatalogReply["filter_options"]>({
    types: [],
    graphs: [],
    strategies: [],
    revision_kinds: [],
  });
  let filters = $state({
    kind: [] as string[],
    graphId: [] as string[],
    strategy: [] as string[],
    revisionKind: [] as string[],
  });
  let loadState = $state<"loading" | "ready" | "error">("loading");
  let isOpening = $state(false);
  let search = $state("");
  let page = $state(1);
  let perPage = $state(8);
  let loadSequence = 0;

  const columns: readonly FilterableTableColumn<DocumentCatalogItem>[] = [
    {
      key: "kind",
      header: kindHeader,
      getValue: (item) => DocumentCatalogDocument.kindLabel(item.kind),
      filterable: true,
    },
    {
      key: "graph",
      header: graphHeader,
      getValue: (item) => item.graph_title,
      filterable: true,
    },
    {
      key: "revision",
      header: revisionKindHeader,
      getValue: revisionLabel,
      filterable: true,
    },
    {
      key: "strategy",
      header: strategyHeader,
      getValue: (item) => item.strategy ?? "",
      filterable: true,
    },
    {
      key: "created",
      header: "Created",
      getValue: (item) => item.created_at,
      filterable: true,
    },
  ];

  const selectedItems = $derived(document.chosenItems);
  const bulkSelectionKeys = $derived(
    document.showingRelated
      ? document.relatedItems.map((item) => item.id)
      : undefined,
  );
  const bulkSelectionLabel = $derived(
    document.showingRelated
      ? "Select related documents"
      : "Select visible documents",
  );
  const kindOptions = $derived(
    filterOptions.types.map((value) => ({
      value,
      label: DocumentCatalogDocument.kindLabel(value),
    })),
  );
  const graphOptions = $derived(
    filterOptions.graphs.map(({ id, title }) => ({ value: id, label: title })),
  );
  const strategyOptions = $derived(options(filterOptions.strategies));
  const revisionKindOptions = $derived(options(filterOptions.revision_kinds));
  const hasActiveFilters = $derived(
    search.length > 0 ||
      Object.values(filters).some((values) => values.length > 0),
  );
  const emptyMessage = $derived(
    loadState === "loading"
      ? "Loading documents…"
      : loadState === "error"
        ? "Could not load documents."
        : hasActiveFilters
          ? "No documents match the selected filters."
          : "No documents found.",
  );

  onMount(() => {
    void loadCatalog();
  });

  async function loadCatalog(): Promise<void> {
    const sequence = ++loadSequence;
    const query = catalogQuery();
    loadState = "loading";
    try {
      const reply = await api.fetchDocumentCatalog(query);
      if (sequence !== loadSequence) return;

      const finalPage = Math.max(1, Math.ceil(reply.total_count / query.limit));
      if (reply.total_count > 0 && page > finalPage) {
        page = finalPage;
        void loadCatalog();
        return;
      }

      items = reply.items;
      totalCount = reply.total_count;
      filterOptions = reply.filter_options;
      document.rememberItems(reply.items, reply.related_items);
      loadState = "ready";
    } catch {
      if (sequence !== loadSequence) return;
      items = [];
      totalCount = 0;
      loadState = "error";
    }
  }

  function catalogQuery(): DocumentCatalogQuery {
    return {
      search,
      types: [...filters.kind],
      graph_ids: [...filters.graphId],
      related_graph_ids: [...document.relatedGraphIds],
      strategies: [...filters.strategy],
      revision_kinds: [...filters.revisionKind],
      limit: perPage,
      offset: (page - 1) * perPage,
    };
  }

  function options(values: readonly string[]): MultiSelectFilterOption[] {
    return values.map((value) => ({ value, label: value }));
  }

  function setFilter(key: keyof typeof filters, values: string[]): void {
    filters[key] = values;
    page = 1;
    void loadCatalog();
  }

  function toggleRelated(): void {
    if (document.showingRelated) {
      document.hideRelated();
    } else if (!document.showRelated()) {
      return;
    }

    page = 1;
    void loadCatalog();
  }

  function updateTableQuery({
    search: nextSearch,
    page: nextPage,
    perPage: nextPerPage,
  }: FilterableTableServerQuery): void {
    search = nextSearch;
    page = nextPage;
    perPage = nextPerPage;
    void loadCatalog();
  }

  async function openSelected(): Promise<void> {
    if (isOpening || loadState === "loading" || selectedItems.length === 0) {
      return;
    }

    isOpening = true;
    try {
      for (const item of selectedItems) {
        try {
          await document.openItem(item);
        } catch {
          // Continue opening the remaining selected documents.
        }
      }
    } finally {
      isOpening = false;
    }
  }

  function revisionLabel(item: DocumentCatalogItem): string {
    const source = `${item.revision_kind} #${item.revision_number}`;
    return item.output_revision_kind != null &&
      item.output_revision_number != null
      ? `${source} -> ${item.output_revision_kind} #${item.output_revision_number}`
      : source;
  }
</script>

{#snippet kindHeader()}
  <div class="catalog-filter-header">
    <span>Type</span>
    <MultiSelectFilter
      label="Type"
      options={kindOptions}
      selectedValues={filters.kind}
      onchange={(values) => setFilter("kind", values)}
      disabled={loadState === "loading" || isOpening}
    />
  </div>
{/snippet}

{#snippet graphHeader()}
  <div class="catalog-filter-header">
    <span>Graph</span>
    <MultiSelectFilter
      label="Graph"
      options={graphOptions}
      selectedValues={filters.graphId}
      onchange={(values) => setFilter("graphId", values)}
      disabled={loadState === "loading" || isOpening}
    />
  </div>
{/snippet}

{#snippet revisionKindHeader()}
  <div class="catalog-filter-header">
    <span>Revision kind</span>
    <MultiSelectFilter
      label="Revision kind"
      options={revisionKindOptions}
      selectedValues={filters.revisionKind}
      onchange={(values) => setFilter("revisionKind", values)}
      disabled={loadState === "loading" || isOpening}
    />
  </div>
{/snippet}

{#snippet strategyHeader()}
  <div class="catalog-filter-header">
    <span>Strategy</span>
    <MultiSelectFilter
      label="Strategy"
      options={strategyOptions}
      selectedValues={filters.strategy}
      onchange={(values) => setFilter("strategy", values)}
      disabled={loadState === "loading" || isOpening}
    />
  </div>
{/snippet}

<article class="document-catalog" aria-labelledby="document-catalog-title">
  <header class="document-catalog-header">
    <div>
      <p>Workspace catalog</p>
      <h1 id="document-catalog-title">{document.title}</h1>
    </div>
    <div class="document-catalog-actions">
      <button
        class="document-catalog-open"
        type="button"
        disabled={loadState === "loading" || isOpening}
        onclick={() => void loadCatalog()}
      >
        Refresh
      </button>
      <button
        class="document-catalog-toggle"
        type="button"
        aria-pressed={document.showingRelated}
        disabled={loadState === "loading" ||
          isOpening ||
          (!document.showingRelated && selectedItems.length === 0)}
        onclick={toggleRelated}
      >
        Show related
      </button>
      <button
        class="document-catalog-open"
        type="button"
        disabled={selectedItems.length === 0 ||
          loadState === "loading" ||
          isOpening}
        onclick={() => void openSelected()}
      >
        Open selected ({selectedItems.length})
      </button>
    </div>
  </header>

  <FilterableTable
    {items}
    {columns}
    getKey={(item) => item.id}
    selectionMode="multiple"
    bind:selectedKeys={
      () => document.chosenKeys, (keys) => document.setChosenKeys(keys)
    }
    {bulkSelectionKeys}
    {bulkSelectionLabel}
    perPage="adaptive"
    server={{ totalCount, page, onchange: updateTableQuery }}
    searchPlaceholder="Search documents…"
    {emptyMessage}
    noMatchMessage="No documents match the search."
    disabled={loadState === "loading" || isOpening}
  />
</article>

<style>
  .document-catalog {
    height: 100%;
    min-height: 0;
    display: grid;
    grid-template-rows: auto minmax(0, 1fr);
    gap: var(--ui-space-4);
    padding: var(--ui-space-6);
    overflow: hidden;
    background: var(--ui-color-surface);
  }

  .document-catalog-header {
    display: flex;
    align-items: end;
    justify-content: space-between;
    gap: var(--ui-space-3);
  }

  .document-catalog-header p,
  .document-catalog-header h1 {
    margin: 0;
  }

  .document-catalog-header p {
    color: var(--ui-color-accent);
    font-size: var(--ui-text-xs);
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .document-catalog-header h1 {
    margin-top: var(--ui-space-1);
    font-size: 1.5rem;
  }

  .document-catalog-actions {
    display: flex;
    gap: var(--ui-space-2);
  }

  .document-catalog-open {
    min-height: var(--ui-control-height);
    padding: 0 var(--ui-space-3);
    border: 1px solid var(--ui-color-accent);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-accent);
    color: var(--ui-color-paper);
    font: inherit;
    white-space: nowrap;
  }

  .document-catalog-toggle {
    min-height: var(--ui-control-height);
    padding: 0 var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    color: var(--ui-color-text);
    font: inherit;
    white-space: nowrap;
  }

  .document-catalog-toggle[aria-pressed="true"] {
    border-color: var(--ui-color-accent);
    background: var(--ui-color-accent-soft);
  }

  .document-catalog-toggle:disabled {
    color: var(--ui-color-text-faint);
    cursor: default;
  }

  .document-catalog-open:disabled {
    border-color: var(--ui-color-border);
    background: var(--ui-color-border-soft);
    color: var(--ui-color-text-faint);
    cursor: default;
  }

  .catalog-filter-header {
    display: inline-flex;
    align-items: center;
    gap: var(--ui-space-1);
  }

  @media (max-width: 48em) {
    .document-catalog {
      padding: var(--ui-space-4);
    }

    .document-catalog-header {
      align-items: start;
      flex-direction: column;
    }
  }
</style>
