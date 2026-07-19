<script lang="ts">
  interface Props {
    documentName: string;
    statusMessage?: string;
  }

  let { documentName, statusMessage }: Props = $props();
</script>

<footer class="dashboard-statusbar">
  <span class="dashboard-status-item">
    <span class="dashboard-valid-dot" aria-hidden="true"></span>Canvas ready
  </span>
  <span class="dashboard-status-item">Blank grid canvas</span>
  {#if statusMessage}
    <span class="dashboard-status-item" role="status">{statusMessage}</span>
  {/if}
  <span class="dashboard-status-item dashboard-status-selection">
    {#if documentName}Document: <strong>{documentName}</strong>{/if}
  </span>
</footer>

<style>
  .dashboard-statusbar {
    grid-area: statusbar;
    display: flex;
    align-items: center;
    gap: 0.875rem;
    padding: 0 0.625rem;
    color: var(--ds-color-on-dark);
    background: var(--ds-color-nav-secondary);
    font-size: var(--ds-text-sm);
  }
  .dashboard-status-item {
    display: flex;
    align-items: center;
    gap: 0.3125rem;
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
  }
  .dashboard-valid-dot {
    width: 0.4375rem;
    height: 0.4375rem;
    border-radius: 50%;
    background: var(--ds-color-status-dot);
  }
  .dashboard-status-selection {
    margin-left: auto;
  }

  @media (max-width: 47.5em) {
    .dashboard-status-item:nth-child(2) {
      display: none;
    }
  }

  @media (forced-colors: active) {
    .dashboard-valid-dot {
      background: CanvasText;
    }
  }
</style>
