<script lang="ts">
  import type { DashboardModel } from "./dashboard/DashboardModel.svelte";
  import AppBar from "./dashboard/shell/AppBar.svelte";
  import StatusBar from "./dashboard/shell/StatusBar.svelte";
  import DashboardInspector from "./dashboard/inspector/DashboardInspector.svelte";
  import DashboardRibbon from "./dashboard/ribbon/DashboardRibbon.svelte";
  import Workspace from "./dashboard/workspace/Workspace.svelte";
  import OptionPickerDialog from "./dashboard/ui/OptionPickerDialog.svelte";
  import Canvas from "./dashboard/graph/canvas/Canvas.svelte";
  import SimulationReport from "./dashboard/simulation-report/SimulationReport.svelte";
  import type { WorkspaceDocument } from "./dashboard/workspace/WorkspaceModel.svelte";
  import type { EditableGraphDocument } from "./dashboard/graph/EditableGraphDocument.svelte";
  import type { SimulationReportDocument } from "./dashboard/simulation-report/SimulationReportDocument.svelte";
  import type { SimulationRunSummary } from "./dashboard/contract";
  import type { GraphSummary } from "./dashboard/contract";

  interface Props {
    model: DashboardModel;
  }

  let { model }: Props = $props();

  const wm = $derived(model.workspace);
  const api = $derived(model.api);

  type DocType = { id: string; label: string; icon: "graph" | "shield" };

  const documentTypes: readonly DocType[] = [
    { id: "graph", label: "Graph", icon: "graph" },
    { id: "simulation-report", label: "Report", icon: "shield" },
  ];

  async function handleSave(): Promise<void> {
    await model.saveActiveGraph();
  }

  function handleForceLayout(): void {
    model.applyForceLayout();
  }

  async function handleRunSimulation(): Promise<void> {
    await model.runActiveSimulation();
  }

  async function handleShowReport(): Promise<void> {
    await model.showReport();
  }

  function formatTimestamp(iso: string): string {
    try {
      return new Date(iso).toLocaleString();
    } catch {
      return iso;
    }
  }

  function formatRuntime(milliseconds: number): string {
    return milliseconds < 1000
      ? `${milliseconds} ms`
      : `${(milliseconds / 1000).toFixed(1)} s`;
  }

  async function handleTopologySelect([
    summary,
  ]: GraphSummary[]): Promise<boolean> {
    return summary ? wm.openGraph(api, summary) : false;
  }

  async function handleSimulationRunSelect([
    run,
  ]: SimulationRunSummary[]): Promise<boolean> {
    return run ? model.selectSimulationRun(run) : false;
  }
</script>

<div class="dashboard-app" data-dashboard-theme="topology">
  <AppBar
    onSave={handleSave}
    saveDisabled={!wm.activeGraph?.saveEligible || wm.activeGraph?.isSaving}
    isSaving={wm.activeGraph?.isSaving ?? false}
  />
  <DashboardRibbon
    hasActiveGraph={wm.hasActiveGraph}
    hasUnreadReport={wm.hasUnreadReport}
    isLoadingSimulationRuns={wm.isLoadingSimulationRuns}
    forceParams={wm.forceParams}
    onForceParamsChange={(change) => wm.onForceParamsChange(change)}
    onForceLayout={handleForceLayout}
    onRunSimulation={handleRunSimulation}
    onShowReport={handleShowReport}
  />

  {#snippet inspector()}
    <DashboardInspector document={wm.activeDocument} />
  {/snippet}

  {#snippet content(document: WorkspaceDocument)}
    {#if document.kind === "graph"}
      <Canvas doc={document as EditableGraphDocument} />
    {:else if document.kind === "simulation-report"}
      <SimulationReport document={document as SimulationReportDocument} />
    {/if}
  {/snippet}

  <Workspace model={wm} {documentTypes} {inspector} {content} />

  <OptionPickerDialog
    open={wm.topologyPickerOpen}
    onOpenChange={(open) => (wm.topologyPickerOpen = open)}
    items={wm.graphSummaries}
    title="Open topology"
    description="Select a saved network topology to open in the workspace."
    getKey={(summary) => summary.id}
    getTitle={(summary) => summary.title}
    getDescription={(summary) =>
      `${summary.nodeCount} node${summary.nodeCount !== 1 ? "s" : ""}, ${summary.edgeCount} edge${summary.edgeCount !== 1 ? "s" : ""}`}
    emptyMessage="No saved topologies."
    status={wm.topologyPickerStatus}
    onConfirm={handleTopologySelect}
  />

  <OptionPickerDialog
    open={wm.simulationRunsModalOpen}
    onOpenChange={(open) => (wm.simulationRunsModalOpen = open)}
    items={wm.simulationRuns}
    title="Simulation runs"
    description="Select a completed simulation run to view its report."
    getKey={(run) => run.id}
    getTitle={(run) => run.graph_title}
    getDescription={(run) =>
      `${run.simulation_count} trials · ${run.iteration_count} iters · ${formatRuntime(run.runtime_ms)} · ${formatTimestamp(run.started_at)}`}
    emptyMessage="No simulation runs found."
    status={wm.simulationRunsStatus}
    onConfirm={handleSimulationRunSelect}
  />

  <StatusBar
    documentName={wm.activeGraph?.title ?? ""}
    statusMessage={wm.statusMessage}
  />
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
    font: var(--ds-text-lg) / var(--ds-line-height) var(--ds-font-ui);
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
