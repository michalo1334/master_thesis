<script lang="ts">
  import { onMount } from "svelte";
  import type { DashboardApi, DocumentCatalogQuery } from "../dashboard-api";
  import type {
    DocumentCatalogItem,
    FetchDocumentCatalogReply,
  } from "../contract";
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
    onOpen: (item: DocumentCatalogItem) => Promise<boolean> | boolean;
  }

  let { document, api, onOpen }: Props = $props();
  let items = $state.raw<DocumentCatalogItem[]>([]);
  let totalCount = $state(0);
  let filterOptions = $state.raw<FetchDocumentCatalogReply["filter_options"]>({
    types: [],
    graphs: [],
    analyses: [],
    strategies: [],
    revision_kinds: [],
  });
  let selectedKeys = $state<string[]>([]);
  let visitedItems = $state.raw<Map<string, DocumentCatalogItem>>(new Map());
  let filters = $state({
    kind: [] as string[],
    analysisId: [] as string[],
    graphId: [] as string[],
    strategy: [] as string[],
    revisionKind: [] as string[],
  });
  let loadState = $state<"loading" | "ready" | "error">("loading");
  let isOpening = $state(false);
  let search = $state("");
  let page = $state(1);
  let perPage = $state(8);

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
      key: "analysis",
      header: analysisHeader,
      getValue: analysisLabel,
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

  const selectedItems = $derived.by(() =>
    selectedKeys.flatMap((key) => {
      const item = visitedItems.get(key);
      return item ? [item] : [];
    }),
  );
  const kindOptions = $derived(
    filterOptions.types.map((value) => ({
      value,
      label: DocumentCatalogDocument.kindLabel(value),
    })),
  );
  const analysisOptions = $derived(
    filterOptions.analyses.map(({ id, title }) => ({
      value: id,
      label: title,
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
    const query = catalogQuery();
    loadState = "loading";
    try {
      const reply = await api.fetchDocumentCatalog(query);

      const finalPage = Math.max(1, Math.ceil(reply.total_count / query.limit));
      if (reply.total_count > 0 && page > finalPage) {
        page = finalPage;
        void loadCatalog();
        return;
      }

      items = reply.items;
      totalCount = reply.total_count;
      filterOptions = reply.filter_options;
      visitedItems = new Map([
        ...visitedItems,
        ...reply.items.map((item) => [item.id, item] as const),
      ]);
      loadState = "ready";
    } catch {
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
      analysis_ids: [...filters.analysisId],
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
    selectedKeys = [];
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
          await onOpen(item);
        } catch {
          // Continue opening the remaining selected documents.
        }
      }
    } finally {
      isOpening = false;
    }
  }

  function analysisLabel(item: DocumentCatalogItem): string {
    const analyses = item.analyses;
    return analyses.length === 1
      ? analyses[0]!.title
      : analyses.length > 1
        ? "Multiple analyses"
        : "";
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

{#snippet analysisHeader()}
  <div class="catalog-filter-header">
    <span>Analyses</span>
    <MultiSelectFilter
      label="Analyses"
      options={analysisOptions}
      selectedValues={filters.analysisId}
      onchange={(values) => setFilter("analysisId", values)}
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
    bind:selectedKeys
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
    gap: var(--ds-space-4);
    padding: var(--ds-space-6);
    overflow: hidden;
    background: var(--ds-color-surface);
  }

  .document-catalog-header {
    display: flex;
    align-items: end;
    justify-content: space-between;
    gap: var(--ds-space-3);
  }

  .document-catalog-header p,
  .document-catalog-header h1 {
    margin: 0;
  }

  .document-catalog-header p {
    color: var(--ds-color-accent);
    font-size: var(--ds-text-xs);
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .document-catalog-header h1 {
    margin-top: var(--ds-space-1);
    font-size: 1.5rem;
  }

  .document-catalog-actions {
    display: flex;
    gap: var(--ds-space-2);
  }

  .document-catalog-open {
    min-height: var(--ds-control-height);
    padding: 0 var(--ds-space-3);
    border: 1px solid var(--ds-color-accent);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-accent);
    color: var(--ds-color-paper);
    font: inherit;
    white-space: nowrap;
  }

  .document-catalog-open:disabled {
    border-color: var(--ds-color-border);
    background: var(--ds-color-border-soft);
    color: var(--ds-color-text-faint);
    cursor: default;
  }

  .catalog-filter-header {
    display: inline-flex;
    align-items: center;
    gap: var(--ds-space-1);
  }

  @media (max-width: 48em) {
    .document-catalog {
      padding: var(--ds-space-4);
    }

    .document-catalog-header {
      align-items: start;
      flex-direction: column;
    }
  }
</style>
