<script lang="ts">
  interface Props {
    progress: { completed: number; total: number; detail?: string } | null;
    waitingMessage: string;
    label: string;
  }

  let { progress, waitingMessage, label }: Props = $props();
</script>

{#if progress && progress.total > 0}
  <div class="report-progress">
    <progress
      max={progress.total}
      value={progress.completed}
      aria-label={`${progress.completed} of ${progress.total} ${label}`}
    ></progress>
    <span class="report-progress-label">
      {progress.completed} of {progress.total}
      {label}
    </span>
    {#if progress.detail}
      <span class="report-progress-detail">{progress.detail}</span>
    {/if}
  </div>
{:else}
  <span class="report-progress-spinner" aria-hidden="true"></span>
  <p>{waitingMessage}</p>
{/if}

<style>
  .report-progress {
    display: grid;
    gap: var(--ui-space-2);
    justify-items: center;
    width: 18rem;
  }

  .report-progress progress {
    width: 100%;
    height: 0.5rem;
    border: 0;
    border-radius: var(--ui-radius-sm);
    overflow: hidden;
  }

  .report-progress progress::-webkit-progress-bar {
    background: var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
  }

  .report-progress progress::-webkit-progress-value {
    background: var(--ui-color-accent);
    border-radius: var(--ui-radius-sm);
  }

  .report-progress progress::-moz-progress-bar {
    background: var(--ui-color-accent);
    border-radius: var(--ui-radius-sm);
  }

  .report-progress-label,
  .report-progress-detail {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }

  .report-progress-spinner {
    width: 2rem;
    height: 2rem;
    border: 3px solid var(--ui-color-border);
    border-top-color: var(--ui-color-accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
