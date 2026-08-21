<script lang="ts">
  import type { DashboardModel } from "./dashboard/DashboardModel.svelte";
  import { AppBar, StatusBar } from "./ui-kit/layout";
  import DashboardInspector from "./dashboard/inspector/DashboardInspector.svelte";
  import DashboardRibbon from "./dashboard/ribbon/DashboardRibbon.svelte";
  import Workspace from "./dashboard/workspace/Workspace.svelte";
  import GraphTreePickerDialog from "./dashboard/workspace/GraphTreePickerDialog.svelte";
  import type { SplitButtonOption } from "./ui-kit/primitives/SplitButton.svelte";
  import ManifestDialog from "./dashboard/manifest/ManifestDialog.svelte";
  import type { WorkspaceDocument } from "./dashboard/workspace/WorkspaceModel.svelte";
  import type { GraphSummary, OptimizationParams } from "./dashboard/contract";
  import { dashboardRegistry } from "./dashboard/workspace/dashboard-registry";

  interface Props {
    model: DashboardModel;
  }

  let { model }: Props = $props();

  const wm = $derived(model.workspace);
  const api = $derived(model.api);

  const downloadResultsHref = $derived.by(() => {
    const doc = wm.activeDocument;
    if (doc?.kind !== "analysis-report") return undefined;
    if (doc.reportData?.status !== "completed") return undefined;
    return `/evaluations/${doc.runId}/download`;
  });

  type OptimizationOption = SplitButtonOption & {
    id: OptimizationParams["strategy"];
  };

  const optimizationOptions: readonly OptimizationOption[] = [
    { id: "cvss", icon: "shield", title: "CVSS" },
    {
      id: "simulation_informed",
      icon: "graph",
      title: "Simulation-informed",
    },
    {
      id: "topology_segmentation",
      icon: "graph",
      title: "Topology segmentation",
    },
    {
      id: "simulated_annealing",
      icon: "shield",
      title: "Simulated annealing",
    },
  ];

  async function handleSave(): Promise<void> {
    await model.saveActiveGraph();
  }

  function handleForceLayout(): void {
    model.applyForceLayout();
  }

  function handleArrangeNetwork(): void {
    wm.activeGraph?.arrangeNetwork();
  }

  async function handleRunSimulation(): Promise<void> {
    await model.runActiveSimulation();
  }

  function handleOptimize(strategyId: OptimizationParams["strategy"]): void {
    wm.onOptimizationParamsChange({ strategy: strategyId });
    void model.runActiveOptimization();
  }

  async function handleTopologySelect(summary: GraphSummary): Promise<boolean> {
    return wm.openGraph(api, summary);
  }

  async function handleGraphComparisonSelect(
    summary: GraphSummary,
  ): Promise<boolean> {
    return wm.selectGraphForComparison(api, summary);
  }

  async function handleFavoriteChange(
    summary: GraphSummary,
    favorite: boolean,
  ): Promise<boolean> {
    return wm.setGraphRevisionFavorite(api, summary, favorite);
  }

  async function handleCreateFolder(name: string): Promise<boolean> {
    return wm.createFolder(api, name);
  }

  async function handleDeleteFolder(folderId: string): Promise<boolean> {
    return wm.deleteFolder(api, folderId);
  }

  async function handleMoveGraph(
    graphId: string,
    folderId: string | null,
  ): Promise<boolean> {
    return wm.moveGraphToFolder(api, graphId, folderId);
  }
</script>

<div class="dashboard-app" data-dashboard-theme="topology">
  <AppBar
    onSave={handleSave}
    saveDisabled={!wm.activeGraph?.loaded ||
      !wm.activeGraph?.isDirty ||
      wm.activeGraph?.isSaving}
    isSaving={wm.activeGraph?.isSaving ?? false}
  />
  <DashboardRibbon
    hasActiveGraph={wm.hasActiveGraph}
    forceParams={wm.forceParams}
    onForceParamsChange={(change) => wm.onForceParamsChange(change)}
    onForceLayout={handleForceLayout}
    onArrangeNetwork={handleArrangeNetwork}
    onRunSimulation={handleRunSimulation}
    onCompareGraphs={() => wm.beginGraphComparison()}
    onOpenAnalysis={() => model.manifest.openDialog()}
    onOptimize={handleOptimize}
    {optimizationOptions}
    activeOptimizationId={wm.optimizationParams.strategy}
    optimizationParams={wm.optimizationParams}
    onOptimizationParamsChange={(change) =>
      wm.onOptimizationParamsChange(change)}
    onSimulationParamsChange={(change) => wm.onSimulationParamsChange(change)}
    simulationParams={wm.simulationParams}
    footholdHosts={wm.activeFootholdHosts}
    {downloadResultsHref}
  />

  {#snippet inspector()}
    <DashboardInspector
      document={wm.activeDocument}
      {api}
      summaries={wm.graphSummaries}
      onOpenParent={(revisionId) => void wm.openGraphRevision(api, revisionId)}
    />
  {/snippet}

  {#snippet content(document: WorkspaceDocument)}
    {@const View = dashboardRegistry[document.kind]?.view}
    {#if View}
      <View {document} {api} />
    {/if}
  {/snippet}

  <div class="dashboard-workspace-layout">
    <Workspace
      model={wm}
      {content}
      onCreateFolder={handleCreateFolder}
      onDeleteFolder={handleDeleteFolder}
      onMoveGraph={handleMoveGraph}
    />
    <div class="dashboard-inspector-slot">
      {@render inspector()}
    </div>
  </div>

  <GraphTreePickerDialog
    open={wm.topologyPickerOpen}
    onOpenChange={(open) => (wm.topologyPickerOpen = open)}
    summaries={wm.graphSummaries}
    status={wm.topologyPickerStatus}
    onSelect={handleTopologySelect}
    onFavoriteChange={handleFavoriteChange}
  />

  <GraphTreePickerDialog
    open={wm.graphComparisonPickerOpen}
    onOpenChange={(open) => wm.setGraphComparisonPickerOpen(open)}
    summaries={wm.graphSummaries}
    status={wm.graphComparisonPickerStatus}
    title={wm.graphComparisonPickerTitle}
    description={wm.graphComparisonPickerDescription}
    selectedRevisionId={wm.graphComparisonBase?.revision_id ?? undefined}
    onSelect={handleGraphComparisonSelect}
    onFavoriteChange={handleFavoriteChange}
  />

  <ManifestDialog model={model.manifest} />

  <StatusBar
    documentName={wm.activeDocument?.title ?? ""}
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
      "appbar" minmax(var(--ui-appbar-height), auto)
      "ribbon" minmax(var(--ui-ribbon-height), auto)
      "workspace" minmax(0, 1fr)
      "statusbar" minmax(var(--ui-statusbar-height), auto)
      / minmax(0, 1fr);
    overflow: hidden;
    color: var(--ui-color-text);
    background: var(--ui-color-surface);
    font: var(--ui-text-lg) / var(--ui-line-height) var(--ui-font-ui);
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
  .dashboard-workspace-layout {
    grid-area: workspace;
    display: grid;
    grid-template-columns: minmax(0, 1fr) var(--ui-inspector-width);
    min-width: 0;
    min-height: 0;
  }

  .dashboard-inspector-slot {
    min-width: 0;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }

  @media (max-width: 47.5em) {
    .dashboard-inspector-slot {
      display: none;
    }
    .dashboard-workspace-layout {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  .dashboard-app :global(:focus-visible) {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: 2px;
  }
</style>
