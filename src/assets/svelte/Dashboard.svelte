<script lang="ts">
  import type { GraphSummary } from "./contracts.generated/dashboard/graph";
  import type { OptimizationParams } from "./contracts.generated/optimization";
  import { tick } from "svelte";

  import type { DashboardModel } from "./dashboard/DashboardModel.svelte";
  import { AppBar, StatusBar } from "./ui-kit/layout";
  import DashboardInspector from "./dashboard/inspector/DashboardInspector.svelte";
  import DashboardRibbon from "./dashboard/ribbon/DashboardRibbon.svelte";
  import Workspace from "./dashboard/workspace/Workspace.svelte";
  import GraphTreePickerDialog from "./dashboard/workspace/GraphTreePickerDialog.svelte";
  import type { SplitButtonOption } from "./ui-kit/primitives/SplitButton.svelte";
  import ManifestDialog from "./dashboard/manifest/ManifestDialog.svelte";
  import type { WorkspaceDocument } from "./dashboard/workspace/WorkspaceModel.svelte";
  import { dashboardRegistry } from "./dashboard/workspace/dashboard-registry";
  import {
    readStudyResultsArchive,
    MAX_STUDY_RESULTS_ARCHIVE_BYTES,
  } from "./dashboard/analysis-report/study-results-import";

  interface Props {
    model: DashboardModel;
  }

  let { model }: Props = $props();

  const wm = $derived(model.workspace);
  const api = $derived(model.api);
  let studyResultsInput = $state<HTMLInputElement>();
  let studyResultsStatus = $state<HTMLElement>();
  let isImportingStudyResults = $state(false);
  let activeStudyResultsImport = 0;

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

  function openStudyResults(): void {
    if (!isImportingStudyResults) studyResultsInput?.click();
  }

  async function focusStudyResultsStatus(): Promise<void> {
    await tick();
    studyResultsStatus?.focus();
  }

  async function importStudyResults(event: Event): Promise<void> {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    input.value = "";

    if (isImportingStudyResults) return;
    if (!file) {
      wm.statusMessage = "Select a non-empty study result ZIP.";
      await focusStudyResultsStatus();
      return;
    }

    const importId = ++activeStudyResultsImport;
    isImportingStudyResults = true;
    wm.statusMessage = "Opening study results…";
    await focusStudyResultsStatus();

    try {
      const archive = await readStudyResultsArchive(file);
      if (importId !== activeStudyResultsImport) return;

      if (archive.status !== "ok") {
        wm.statusMessage =
          archive.status === "empty"
            ? "Select a non-empty study result ZIP."
            : `Study result ZIP must not exceed ${MAX_STUDY_RESULTS_ARCHIVE_BYTES / 1024 / 1024} MB.`;
        await focusStudyResultsStatus();
        return;
      }

      const reply = await api.importStudyResults({ archive: archive.archive });
      if (importId !== activeStudyResultsImport) return;

      if (reply.status !== "ok" || !reply.analysis) {
        wm.statusMessage = `${reply.error?.message ?? "Could not open study results."} Select a valid mix evaluate.study result ZIP.`;
        await focusStudyResultsStatus();
        return;
      }

      const studyDocument = wm.openImportedStudyResults(reply.analysis);
      wm.statusMessage = "";
      await tick();
      globalThis.document
        .querySelector<HTMLElement>(
          `[data-imported-study-results="${studyDocument.id}"]`,
        )
        ?.focus();
    } catch {
      if (importId !== activeStudyResultsImport) return;
      wm.statusMessage =
        "Could not open study results. Select a valid mix evaluate.study result ZIP.";
      await focusStudyResultsStatus();
    } finally {
      if (importId === activeStudyResultsImport) {
        isImportingStudyResults = false;
      }
    }
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
    onRunSimulation={handleRunSimulation}
    onCompareGraphs={() => wm.beginGraphComparison()}
    onOpenAnalysis={() => model.manifest.openDialog()}
    onOpenStudyResults={openStudyResults}
    {isImportingStudyResults}
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
  <input
    bind:this={studyResultsInput}
    class="study-results-input"
    type="file"
    accept=".zip,application/zip"
    aria-label="Select study results ZIP"
    onchange={(event) => void importStudyResults(event)}
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
      <View
        {document}
        {api}
        onCancel={document.isAsyncReportDocument()
          ? () => model.cancelReport(document)
          : undefined}
      />
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
    bind:statusElement={studyResultsStatus}
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

  .study-results-input {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
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
