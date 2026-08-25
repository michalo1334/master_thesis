<script lang="ts">
  import { onMount } from "svelte";
  import type { RunSummary } from "../../contracts.generated";
  import FilterableTable from "../../ui-kit/composites/FilterableTable.svelte";
  import type { FilterableTableColumn } from "../../ui-kit/composites/FilterableTable.types";
  import { formatTimestamp } from "../format";
  import type { DashboardApi } from "../dashboard-api";
  import { RunsDocument } from "./RunsDocument.svelte";

  interface Props {
    document: RunsDocument;
    api: DashboardApi;
  }

  let { document, api }: Props = $props();
  let runs = $state.raw<RunSummary[]>([]);
  let loadState = $state<"loading" | "ready" | "error">("loading");
  let selectedKeys = $state<string[]>([]);
  let cancelling = $state(false);
  let actionMessage = $state("");
  const selectedRun = $derived(runs.find((run) => run.id === selectedKeys[0]));

  function isCancellableRunKind(
    kind: string,
  ): kind is "simulation" | "optimization" | "evaluation" {
    return (
      kind === "simulation" || kind === "optimization" || kind === "evaluation"
    );
  }

  async function cancelSelected(): Promise<void> {
    const run = selectedRun;
    if (!run || cancelling || !globalThis.confirm("Cancel this run?")) return;
    if (!isCancellableRunKind(run.kind)) {
      actionMessage = "Could not cancel run.";
      return;
    }
    cancelling = true;
    actionMessage = "";
    try {
      const reply = await api.cancelRun({
        kind: run.kind,
        run_id: run.id,
      });
      if (reply.status === "cancelled") {
        actionMessage = "Run cancelled.";
        selectedKeys = [];
        await loadRuns();
      } else {
        actionMessage = `Could not cancel run (${reply.status}).`;
      }
    } catch {
      actionMessage = "Could not cancel run.";
    } finally {
      cancelling = false;
    }
  }

  const columns: readonly FilterableTableColumn<RunSummary>[] = [
    {
      key: "kind",
      header: "Kind",
      getValue: (run) => run.kind,
      filterable: true,
    },
    {
      key: "title",
      header: "Title",
      getValue: (run) => run.title ?? "",
      filterable: true,
    },
    {
      key: "progress",
      header: "Progress",
      getValue: progress,
      filterable: true,
    },
    {
      key: "status",
      header: "Status",
      getValue: (run) => run.status,
      filterable: true,
    },
    {
      key: "started",
      header: "Started",
      getValue: (run) =>
        run.started_at ? formatTimestamp(run.started_at) : "",
      filterable: true,
    },
  ];

  const emptyMessage = $derived(
    loadState === "loading"
      ? "Loading runs…"
      : loadState === "error"
        ? "Could not load runs."
        : "No active runs.",
  );

  onMount(() => {
    void loadRuns();
  });

  async function loadRuns(): Promise<void> {
    loadState = "loading";
    try {
      runs = (await api.fetchRuns()).runs;
      loadState = "ready";
    } catch {
      runs = [];
      loadState = "error";
    }
  }

  function progress(run: RunSummary): string {
    return run.completed != null && run.total != null
      ? `${run.completed} / ${run.total}`
      : "";
  }
</script>

<article class="runs" aria-labelledby="runs-title">
  <header class="runs-header">
    <div>
      <p>Active work</p>
      <h1 id="runs-title">{document.title}</h1>
    </div>
    <div class="runs-actions">
      <button
        class="runs-refresh"
        type="button"
        disabled={!selectedRun || cancelling}
        onclick={() => void cancelSelected()}
      >
        {cancelling ? "Cancelling…" : "Cancel selected"}
      </button>
      <button
        class="runs-refresh"
        type="button"
        disabled={loadState === "loading"}
        onclick={() => void loadRuns()}
      >
        Refresh
      </button>
    </div>
  </header>

  <p class="runs-status" aria-live="polite">{actionMessage}</p>

  <FilterableTable
    items={runs}
    {columns}
    getKey={(run) => run.id}
    selectionMode="single"
    bind:selectedKeys
    {emptyMessage}
    noMatchMessage="No runs match the search."
    disabled={loadState === "loading"}
  />
</article>

<style>
  .runs {
    height: 100%;
    min-height: 0;
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr);
    gap: var(--ui-space-4);
    padding: var(--ui-space-6);
    overflow: hidden;
    background: var(--ui-color-surface);
  }

  .runs-header {
    display: flex;
    align-items: end;
    justify-content: space-between;
    gap: var(--ui-space-3);
  }

  .runs-actions {
    display: flex;
    gap: var(--ui-space-2);
  }
  .runs-status {
    min-height: 1.5em;
    margin: 0;
    color: var(--ui-color-text-secondary);
  }

  .runs-header p,
  .runs-header h1 {
    margin: 0;
  }

  .runs-header p {
    color: var(--ui-color-accent);
    font-size: var(--ui-text-xs);
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .runs-header h1 {
    margin-top: var(--ui-space-1);
    font-size: 1.5rem;
  }

  .runs-refresh {
    min-height: var(--ui-control-height);
    padding: 0 var(--ui-space-3);
    border: 1px solid var(--ui-color-accent);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-accent);
    color: var(--ui-color-paper);
    font: inherit;
  }

  .runs-refresh:disabled {
    border-color: var(--ui-color-border);
    background: var(--ui-color-border-soft);
    color: var(--ui-color-text-faint);
    cursor: default;
  }

  @media (max-width: 48em) {
    .runs {
      padding: var(--ui-space-4);
    }
  }
</style>
