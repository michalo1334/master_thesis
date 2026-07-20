<script lang="ts">
  import { Dialog } from "bits-ui";
  import type { SimulationRunSummary } from "../contract";

  interface Props {
    open: boolean;
    runs: SimulationRunSummary[];
    onOpenChange: (open: boolean) => void;
    onSelect: (run: SimulationRunSummary) => void;
    status?: string;
  }

  let { open, runs, onOpenChange, onSelect, status = "" }: Props = $props();

  function formatTimestamp(iso: string): string {
    try {
      const d = new Date(iso);
      return d.toLocaleString();
    } catch {
      return iso;
    }
  }

  function formatRuntime(ms: number): string {
    if (ms < 1000) return `${ms} ms`;
    return `${(ms / 1000).toFixed(1)} s`;
  }
</script>

<Dialog.Root {open} {onOpenChange}>
  <Dialog.Portal>
    <Dialog.Overlay class="simulation-runs-overlay" />
    <Dialog.Content class="simulation-runs-dialog">
      <Dialog.Title>Simulation runs</Dialog.Title>
      <Dialog.Description>
        Select a completed simulation run to view its report.
      </Dialog.Description>

      <div class="simulation-runs-list" aria-label="Simulation runs">
        {#if runs.length === 0}
          <p class="simulation-runs-empty">No simulation runs found.</p>
        {:else}
          {#each runs as run (run.id)}
            <button
              class="simulation-runs-item"
              type="button"
              onclick={() => onSelect(run)}
            >
              <span class="simulation-runs-title">{run.graph_title}</span>
              <span class="simulation-runs-meta">
                {run.simulation_count} trials &middot; {run.iteration_count}
                iters &middot; {formatRuntime(run.runtime_ms)}
              </span>
              <span class="simulation-runs-date">
                {formatTimestamp(run.started_at)}
              </span>
            </button>
          {/each}
        {/if}
      </div>

      {#if status}
        <p class="simulation-runs-status" role="alert">{status}</p>
      {/if}

      <Dialog.Close
        class="simulation-runs-close"
        aria-label="Close simulation runs dialog"
      >
        ×
      </Dialog.Close>
    </Dialog.Content>
  </Dialog.Portal>
</Dialog.Root>

<style>
  :global(.simulation-runs-overlay) {
    position: fixed;
    z-index: 200;
    inset: 0;
    background: color-mix(in srgb, var(--ds-color-nav) 45%, transparent);
  }
  :global(.simulation-runs-dialog) {
    position: fixed;
    z-index: 201;
    top: 50%;
    left: 50%;
    width: min(36rem, calc(100vw - 2rem));
    max-height: min(40rem, calc(100dvh - 2rem));
    overflow: auto;
    padding: 1.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-lg);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
    color: var(--ds-color-text);
    transform: translate(-50%, -50%);
  }
  :global(.simulation-runs-dialog [data-dialog-title]) {
    margin: 0;
    font-size: var(--ds-text-xl);
  }
  :global(.simulation-runs-dialog [data-dialog-description]) {
    margin: var(--ds-space-2) 0 0;
    color: var(--ds-color-text-secondary);
  }
  .simulation-runs-list {
    display: grid;
    gap: var(--ds-space-2);
    margin-top: var(--ds-space-4);
  }
  .simulation-runs-item {
    width: 100%;
    padding: var(--ds-space-3);
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-surface);
    color: inherit;
    text-align: left;
  }
  .simulation-runs-item:hover {
    border-color: var(--ds-color-focus);
    background: var(--ds-color-accent-soft);
  }
  .simulation-runs-title,
  .simulation-runs-meta,
  .simulation-runs-date {
    display: block;
  }
  .simulation-runs-title {
    font-weight: 600;
  }
  .simulation-runs-meta {
    margin-top: var(--ds-space-1);
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
    font-variant-numeric: tabular-nums;
  }
  .simulation-runs-date {
    margin-top: var(--ds-space-1);
    color: var(--ds-color-text-faint);
    font-size: var(--ds-text-xs);
  }
  .simulation-runs-empty {
    margin: 0;
    padding: var(--ds-space-4);
    color: var(--ds-color-text-secondary);
    text-align: center;
  }
  .simulation-runs-status {
    margin: var(--ds-space-3) 0 0;
    padding: var(--ds-space-2) var(--ds-space-3);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-warning-bg);
    color: var(--ds-color-warning-text);
    font-size: var(--ds-text-sm);
  }
  :global(.simulation-runs-close) {
    position: absolute;
    top: var(--ds-space-2);
    right: var(--ds-space-2);
    display: grid;
    width: 2rem;
    height: 2rem;
    place-items: center;
    border: 0;
    border-radius: var(--ds-radius-sm);
    background: transparent;
    color: var(--ds-color-text-secondary);
    font-size: 1.5rem;
    line-height: 1;
  }
  :global(.simulation-runs-close:hover) {
    background: var(--ds-color-accent-soft);
    color: var(--ds-color-text);
  }
</style>
