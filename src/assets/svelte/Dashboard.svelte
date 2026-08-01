<script lang="ts">
  import type { DashboardModel } from "./dashboard/DashboardModel.svelte";
  import AppBar from "./dashboard/shell/AppBar.svelte";
  import StatusBar from "./dashboard/shell/StatusBar.svelte";
  import DashboardInspector from "./dashboard/inspector/DashboardInspector.svelte";
  import DashboardRibbon from "./dashboard/ribbon/DashboardRibbon.svelte";
  import Workspace from "./dashboard/workspace/Workspace.svelte";
  import OptionPickerDialog from "./dashboard/ui/OptionPickerDialog.svelte";
  import GraphTreePickerDialog from "./dashboard/workspace/GraphTreePickerDialog.svelte";
  import type { SplitButtonOption } from "./dashboard/ui/SplitButton.svelte";
  import EditableCanvas from "./dashboard/graph/canvas/EditableCanvas.svelte";
  import GraphDiff from "./dashboard/graph/GraphDiff.svelte";
  import SimulationReport from "./dashboard/simulation-report/SimulationReport.svelte";
  import OptimizationReport from "./dashboard/optimization-report/OptimizationReport.svelte";
  import type { WorkspaceDocument } from "./dashboard/workspace/WorkspaceModel.svelte";
  import type { EditableGraphDocument } from "./dashboard/graph/EditableGraphDocument.svelte";
  import type { SimulationReportDocument } from "./dashboard/simulation-report/SimulationReportDocument.svelte";
  import type { OptimizationReportDocument } from "./dashboard/optimization-report/OptimizationReportDocument.svelte";
  import type { GraphDiffDocument } from "./dashboard/graph/GraphDiffDocument.svelte";
  import type {
    ExperimentSummary,
    GraphSummary,
    OptimizationParams,
  } from "./dashboard/contract";
  import { formatRuntime, formatTimestamp } from "./dashboard/format";
  import type { FilterableTableColumn } from "./dashboard/controls/FilterableTable.types";

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

  const experimentColumns: FilterableTableColumn<ExperimentSummary>[] = [
    {
      key: "title",
      header: "Graph",
      getValue: (experiment) => experiment.graph_title,
      filterable: true,
    },
    {
      key: "runs",
      header: "Runs",
      getValue: (experiment) => String(experiment.run_count),
      align: "end",
    },
    {
      key: "iters",
      header: "Iters",
      getValue: (experiment) => String(experiment.iteration_count),
      align: "end",
    },
    {
      key: "runtime",
      header: "Runtime",
      getValue: (experiment) => formatRuntime(experiment.runtime_ms),
      align: "end",
      filterable: true,
    },
    {
      key: "started",
      header: "Started",
      getValue: (experiment) => formatTimestamp(experiment.started_at),
      align: "end",
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

  async function handleShowExperiments(): Promise<void> {
    await model.showExperiments();
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

  async function handleExperimentSelect([
    experiment,
  ]: ExperimentSummary[]): Promise<boolean> {
    return experiment ? model.selectExperiment(experiment) : false;
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
    isLoadingExperiments={wm.isLoadingExperiments}
    forceParams={wm.forceParams}
    onForceParamsChange={(change) => wm.onForceParamsChange(change)}
    onForceLayout={handleForceLayout}
    onRunSimulation={handleRunSimulation}
    onShowExperiments={handleShowExperiments}
    onCompareGraphs={() => wm.beginGraphComparison()}
    onOptimize={handleOptimize}
    {optimizationOptions}
    activeOptimizationId={wm.optimizationParams.strategy}
    optimizationParams={wm.optimizationParams}
    onOptimizationParamsChange={(change) =>
      wm.onOptimizationParamsChange(change)}
    onSimulationParamsChange={(change) => wm.onSimulationParamsChange(change)}
    simulationParams={wm.simulationParams}
    footholdHosts={wm.activeFootholdHosts}
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
      <SimulationReport document={document as SimulationReportDocument} />
    {:else if document.kind === "optimization-report"}
      <OptimizationReport document={document as OptimizationReportDocument} />
    {/if}
  {/snippet}

  <Workspace model={wm} {documentTypes} {inspector} {content} />

  <GraphTreePickerDialog
    open={wm.topologyPickerOpen}
    onOpenChange={(open) => (wm.topologyPickerOpen = open)}
    summaries={wm.graphSummaries}
    status={wm.topologyPickerStatus}
    onSelect={handleTopologySelect}
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
  />

  <OptionPickerDialog
    open={wm.experimentsModalOpen}
    onOpenChange={(open) => (wm.experimentsModalOpen = open)}
    items={wm.experiments}
    title="Experiments"
    description="Select a completed experiment to view its report."
    getKey={(experiment) => experiment.id}
    columns={experimentColumns}
    searchPlaceholder="Search experiments…"
    emptyMessage="No experiments found."
    noMatchMessage="No experiments match your search."
    status={wm.experimentsStatus}
    onConfirm={handleExperimentSelect}
  />

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
