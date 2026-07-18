<script lang="ts">
  import { onMount } from "svelte";
  import type { Live } from "live_svelte";
  import { DashboardController } from "./dashboard/DashboardController.svelte";
  import { setDashboardContext } from "./dashboard/dashboard-context";
  import AppBar from "./dashboard/shell/AppBar.svelte";
  import StatusBar from "./dashboard/shell/StatusBar.svelte";
  import DashboardInspector from "./dashboard/DashboardInspector.svelte";
  import DashboardRibbon from "./dashboard/DashboardRibbon.svelte";
  import Workspace from "./dashboard/workspace/Workspace.svelte";
  import TopologyPickerDialog from "./dashboard/workspace/TopologyPickerDialog.svelte";
  interface Props {
    live: Live;
  }

  const { live }: Props = $props();

  const dashboardController = new DashboardController({
    pushEvent: (event, payload, onReply) =>
      live.pushEvent(event, payload, onReply),
  });

  setDashboardContext(dashboardController);
</script>

<div class="dashboard-app" data-dashboard-theme="topology">
  <AppBar onSave={() => {}} isSaving={false} />
  <DashboardRibbon inspectorVisible={true} />

  {#snippet inspector()}
    <DashboardInspector />
  {/snippet}

  <Workspace />
  <TopologyPickerDialog />

  <StatusBar documentName="abc" statusMessage="abc" />
</div>

<style>
  .dashboard-app {
    box-sizing: border-box;
    min-width: 20rem;
    min-height: 100dvh;
    height: 100dvh;
    display: grid;
    grid-template:
      "appbar" minmax(var(--ds-appbar-height), auto)
      "ribbon" minmax(var(--ds-ribbon-height), auto)
      "workspace" minmax(0, 1fr)
      "statusbar" minmax(var(--ds-statusbar-height), auto)
      / minmax(0, 1fr);
    overflow: hidden;
    color: var(--ds-color-text);
    background: var(--ds-color-surface);
    font: var(--ds-text-lg)/var(--ds-line-height) var(--ds-font-ui);
  }

  .dashboard-app :global(*),
  .dashboard-app :global(*::before),
  .dashboard-app :global(*::after) {
    box-sizing: border-box;
  }

  .dashboard-app :global(button),
  .dashboard-app :global(input),
  .dashboard-app :global(select) {
    color: inherit;
    font: inherit;
  }

  .dashboard-app :global(button:not(:disabled)) {
    cursor: pointer;
  }
  .dashboard-app :global(:focus-visible) {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 2px;
  }
</style>
