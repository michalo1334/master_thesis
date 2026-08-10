<script lang="ts">
  import type { DashboardModel } from "./dashboard/DashboardModel.svelte";
  import AppBar from "./dashboard/shell/AppBar.svelte";
  import StatusBar from "./dashboard/shell/StatusBar.svelte";
  import DashboardInspector from "./dashboard/inspector/DashboardInspector.svelte";
  import DashboardRibbon from "./dashboard/ribbon/DashboardRibbon.svelte";
  import Workspace from "./dashboard/workspace/Workspace.svelte";
  import GraphTreePickerDialog from "./dashboard/workspace/GraphTreePickerDialog.svelte";
  import type { SplitButtonOption } from "./dashboard/ui/SplitButton.svelte";
  import EditableCanvas from "./dashboard/graph/canvas/EditableCanvas.svelte";
  import GraphDiff from "./dashboard/graph/GraphDiff.svelte";
  import SimulationReport from "./dashboard/simulation-report/SimulationReport.svelte";
  import OptimizationReport from "./dashboard/optimization-report/OptimizationReport.svelte";
  import AnalysisDialog from "./dashboard/analysis/AnalysisDialog.svelte";
  import type { WorkspaceDocument } from "./dashboard/workspace/WorkspaceModel.svelte";
  import type { EditableGraphDocument } from "./dashboard/graph/EditableGraphDocument.svelte";
  import type { SimulationReportDocument } from "./dashboard/simulation-report/SimulationReportDocument.svelte";
  import type { OptimizationReportDocument } from "./dashboard/optimization-report/OptimizationReportDocument.svelte";
  import type { GraphDiffDocument } from "./dashboard/graph/GraphDiffDocument.svelte";
  import type { GraphSummary, OptimizationParams } from "./dashboard/contract";

  interface Props {
    model: DashboardModel;
  }

  let { model }: Props = $props();

  const wm = $derived(model.workspace);
  const api = $derived(model.api);

  type DocType = { id: string; label: string; icon: "graph" | "shield" };
  type OptimizationOption = SplitButtonOption & {
    id: OptimizationParams["strategy"];
  };

  const documentTypes: readonly DocType[] = [
    { id: "graph", label: "Graph", icon: "graph" },
  ];

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
    onRunSimulation={handleRunSimulation}
    onCompareGraphs={() => wm.beginGraphComparison()}
    onOpenAnalysis={() => model.analysis.openDialog()}
    onOptimize={handleOptimize}
    {optimizationOptions}
    activeOptimizationId={wm.optimizationParams.strategy}
    optimizationParams={wm.optimizationParams}
    onOptimizationParamsChange={(change) =>
      wm.onOptimizationParamsChange(change)}
    onSimulationParamsChange={(change) => wm.onSimulationParamsChange(change)}
    simulationParams={wm.simulationParams}
    footholdHosts={wm.activeFootholdHosts}
    analysisRunning={model.analysis.isRunning}
  />

  {#snippet inspector()}
    <DashboardInspector
      document={wm.activeDocument}
      summaries={wm.graphSummaries}
    />
  {/snippet}

  {#snippet content(document: WorkspaceDocument)}
    {#if document.kind === "graph"}
      <EditableCanvas
        document={document as EditableGraphDocument}
        {api}
        onCompareGraphs={() =>
          wm.beginGraphComparisonWithActive(document as EditableGraphDocument)}
      />
    {:else if document.kind === "graph-diff"}
      <GraphDiff document={document as GraphDiffDocument} />
    {:else if document.kind === "simulation-report"}
      <SimulationReport
        document={document as SimulationReportDocument}
        onOpenSourceGraph={() =>
          wm.openGraphRevision(
            api,
            (document as SimulationReportDocument).graphRevisionId,
          )}
      />
    {:else if document.kind === "optimization-report"}
      <OptimizationReport document={document as OptimizationReportDocument} />
    {/if}
  {/snippet}

  <Workspace
    model={wm}
    {documentTypes}
    {inspector}
    {content}
    onCreateFolder={handleCreateFolder}
    onDeleteFolder={handleDeleteFolder}
    onMoveGraph={handleMoveGraph}
  />

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

  <GraphTreePickerDialog
    open={model.analysis.targetPickerOpen}
    onOpenChange={(open) => model.analysis.setTargetPickerOpen(open)}
    summaries={wm.graphSummaries}
    status={model.analysis.statusMessage}
    title="Select target graph"
    description="Select the saved graph to analyze."
    selectedRevisionId={model.analysis.targetRevisionId || undefined}
    onSelect={(summary) => model.analysis.selectTarget(summary.revision_id)}
    onFavoriteChange={handleFavoriteChange}
  />

  <AnalysisDialog model={model.analysis} {optimizationOptions} />

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
