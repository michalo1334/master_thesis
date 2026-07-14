<script lang="ts">
  interface Props {
    selectedName: string;
    zoom: number;
  }

  let { selectedName, zoom }: Props = $props();
</script>

<footer class="dashboard-statusbar">
  <span class="dashboard-status-item"><span class="dashboard-valid-dot" aria-hidden="true"></span>Topology valid</span>
  <span class="dashboard-status-item">8 assets · 7 relationships · 4 zones</span>
  <span class="dashboard-status-item dashboard-status-selection">Selection: <strong>{selectedName}</strong></span>
  <span class="dashboard-status-item dashboard-status-compact">Zoom: {zoom}% · Grid: 20 px</span>
</footer>

<style>
  .dashboard-statusbar { grid-area: statusbar; display: flex; align-items: center; gap: 0.875rem; padding: 0 0.625rem; color: #d6dfeb; background: var(--ds-color-nav-secondary); font-size: var(--ds-text-sm); }
  .dashboard-status-item { display: flex; align-items: center; gap: 0.3125rem; white-space: nowrap; font-variant-numeric: tabular-nums; }
  .dashboard-valid-dot { width: 0.4375rem; height: 0.4375rem; border-radius: 50%; background: #6cc18a; }
  .dashboard-status-selection { margin-left: auto; }

  @media (max-width: 47.5em) {
    .dashboard-status-item:nth-child(2), .dashboard-status-compact { display: none; }
  }

  @media (forced-colors: active) {
    .dashboard-valid-dot { background: CanvasText; }
  }
</style>
