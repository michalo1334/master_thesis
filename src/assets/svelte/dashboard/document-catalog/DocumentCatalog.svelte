<script lang="ts">
  import { onMount } from "svelte";
  import type { DashboardApi } from "../dashboard-api";
  import type { DocumentCatalogItem } from "../contract";
  import FilterableTable from "../controls/FilterableTable.svelte";
  import type { FilterableTableColumn } from "../controls/FilterableTable.types";
  import MultiSelectFilter from "../controls/MultiSelectFilter.svelte";
  import type { MultiSelectFilterOption } from "../controls/MultiSelectFilter.svelte";
  import type { DocumentCatalogDocument } from "./DocumentCatalogDocument.svelte";

  interface Props {
    document: DocumentCatalogDocument;
    api: DashboardApi;
    onOpen: (item: DocumentCatalogItem) => Promise<boolean> | boolean;
  }

  let { document, api, onOpen }: Props = $props();
  let items = $state.raw<DocumentCatalogItem[]>([]);
  let selectedKeys = $state<string[]>([]);
  let filters = $state({
    kind: [] as string[],
    analysisId: [] as string[],
    graphId: [] as string[],
    strategy: [] as string[],
    revisionKind: [] as string[],
  });
  let loadState = $state<"loading" | "ready" | "error">("loading");
  let isOpening = $state(false);

  const columns: readonly FilterableTableColumn<DocumentCatalogItem>[] = [
    {
      key: "kind",
      header: kindHeader,
      getValue: kindLabel,
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
      getValue: (item) => `${item.revision_kind} #${item.revision_number}`,
      filterable: true,
    },
    {
      key: "analysis",
      header: analysisHeader,
      getValue: (item) => item.analysis_id ?? "",
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

  const filteredItems = $derived.by(() =>
    items.filter(
      (item) =>
        matches(filters.kind, item.kind) &&
        matches(filters.analysisId, item.analysis_id) &&
        matches(filters.graphId, item.graph_id) &&
        matches(filters.strategy, item.strategy) &&
        matches(filters.revisionKind, item.revision_kind),
    ),
  );
  const selectedItems = $derived(
    items.filter((item) => selectedKeys.includes(item.id)),
  );
  const kindOptions: readonly MultiSelectFilterOption[] = [
    { value: "graph", label: "Graph" },
    { value: "simulation_report", label: "Simulation report" },
    { value: "optimization_report", label: "Optimization report" },
  ];
  const analysisOptions = $derived(optionsFor((item) => item.analysis_id));
  const graphOptions = $derived.by(() =>
    [
      ...new Map(
        items.map((item) => [item.graph_id, item.graph_title]),
      ).entries(),
    ]
      .map(([value, label]) => ({ value, label }))
      .sort((a, b) => a.label.localeCompare(b.label)),
  );
  const strategyOptions = $derived(optionsFor((item) => item.strategy));
  const revisionKindOptions = $derived(
    optionsFor((item) => item.revision_kind),
  );
  const hasActiveFilters = $derived(
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
    loadState = "loading";
    try {
      const refreshedItems = (await api.fetchDocumentCatalog()).items;
      const hasValue = (
        getValue: (item: DocumentCatalogItem) => string | null | undefined,
        value: string,
      ) => refreshedItems.some((item) => getValue(item) === value);

      filters.kind = filters.kind.filter((value) =>
        hasValue((item) => item.kind, value),
      );
      filters.analysisId = filters.analysisId.filter((value) =>
        hasValue((item) => item.analysis_id, value),
      );
      filters.graphId = filters.graphId.filter((value) =>
        hasValue((item) => item.graph_id, value),
      );
      filters.strategy = filters.strategy.filter((value) =>
        hasValue((item) => item.strategy, value),
      );
      filters.revisionKind = filters.revisionKind.filter((value) =>
        hasValue((item) => item.revision_kind, value),
      );
      const refreshedKeys = new Set(refreshedItems.map((item) => item.id));
      selectedKeys = selectedKeys.filter((key) => refreshedKeys.has(key));
      items = refreshedItems;
      loadState = "ready";
    } catch {
      items = [];
      loadState = "error";
    }
  }

  function optionsFor(
    getValue: (item: DocumentCatalogItem) => string | null | undefined,
  ): MultiSelectFilterOption[] {
    return [...new Set(items.flatMap((item) => getValue(item) ?? []))]
      .sort()
      .map((value) => ({ value, label: value }));
  }

  function matches(
    selectedValues: readonly string[],
    value: string | null | undefined,
  ): boolean {
    return (
      selectedValues.length === 0 || (!!value && selectedValues.includes(value))
    );
  }

  function setFilter(key: keyof typeof filters, values: string[]): void {
    filters[key] = values;
    selectedKeys = [];
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

  function kindLabel(item: DocumentCatalogItem): string {
    if (item.kind === "simulation_report") return "Simulation report";
    if (item.kind === "optimization_report") return "Optimization report";
    return "Graph";
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
    <span>Analysis ID</span>
    <MultiSelectFilter
      label="Analysis ID"
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
    items={filteredItems}
    {columns}
    getKey={(item) => item.id}
    selectionMode="multiple"
    bind:selectedKeys
    perPage="adaptive"
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
