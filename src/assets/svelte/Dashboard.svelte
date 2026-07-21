<script lang="ts">
  import type { Live } from "live_svelte";
  import { DashboardController } from "./dashboard/DashboardController.svelte";
  import { setDashboardContext } from "./dashboard/dashboard-context";
  import {
    createDashboardServer,
    registerSimulationDoneHandler,
    type LiveServer,
  } from "./dashboard/server";
  import AppBar from "./dashboard/shell/AppBar.svelte";
  import StatusBar from "./dashboard/shell/StatusBar.svelte";
  import DashboardInspector from "./dashboard/DashboardInspector.svelte";
  import DashboardRibbon from "./dashboard/DashboardRibbon.svelte";
  import Workspace from "./dashboard/workspace/Workspace.svelte";
  import TopologyPickerDialog from "./dashboard/workspace/TopologyPickerDialog.svelte";
  import Canvas from "./dashboard/canvas/Canvas.svelte";
  import SimulationReport from "./dashboard/simulation/SimulationReport.svelte";
  import SimulationRunsModal from "./dashboard/simulation/SimulationRunsModal.svelte";
  import type {
    WorkspaceDocument,
    DocumentKind,
  } from "./dashboard/workspace/WorkspaceDocument.svelte";
  import type {
    CanvasDocument,
    CanvasSelection,
  } from "./dashboard/canvas/CanvasDocument.svelte";
  import { SimulationReportDocument } from "./dashboard/simulation/SimulationReportDocument.svelte";
  import type { WorkspaceDocumentType } from "./dashboard/workspace/Workspace.svelte";
  import type {
    GraphSummary,
    SimulationRunSummary,
  } from "./dashboard/contract";
  import type { ForceParams } from "./dashboard/layout/ForceLayout.types";
  import { defaultForceParams } from "./dashboard/layout/ForceLayout.types";

  interface Props {
    live: Live;
    graphSummaries?: GraphSummary[];
  }

  const { live, graphSummaries = [] }: Props = $props();

  const dashboardController = new DashboardController();
  const server = $derived(createDashboardServer(live as LiveServer));

  registerSimulationDoneHandler((payload) => {
    console.log("simulation_done received", payload);
    const activeReport = dashboardController.onSimulationDone(payload);
    console.log("active report after onSimulationDone", {
      hasActiveReport: !!activeReport,
      multiStateId: activeReport?.multiStateId,
    });
    if (activeReport && activeReport.multiStateId) {
      console.log("fetching report for", activeReport.multiStateId);
      server.fetchSimulationReport(
        activeReport.multiStateId,
        activeReport.graphId,
        (data) => {
          console.log("simulation report fetched", data);
          activeReport.setReportData(data);
        },
      );
    }
  });

  setDashboardContext(dashboardController);

  const documentTypes: readonly WorkspaceDocumentType[] = [
    { id: "canvas", label: "Canvas", icon: "graph" },
    { id: "simulation-report", label: "Report", icon: "shield" },
  ];

  // -- dialog state --
  let topologyPickerOpen = $state(false);
  let topologyPickerStatus = $state("");
  let simulationRunsModalOpen = $state(false);
  let simulationRuns = $state<SimulationRunSummary[]>([]);
  let simulationRunsStatus = $state("");

  // -- save state --
  let isSaving = $state(false);
  let statusMessage = $state("");

  // -- layout state --
  let forceParams = $state<ForceParams>({ ...defaultForceParams });

  // Increment after force layout to trigger Canvas fit-to-view.
  let fitToViewCounter = $state(0);

  // -- derived from active document --
  let activeCanvasDoc = $derived.by(() => {
    const doc = dashboardController.activeDocument;
    if (!doc || doc.kind !== "canvas") return undefined;
    return doc as CanvasDocument;
  });

  let saveDisabled = $derived(
    isSaving || !activeCanvasDoc || !activeCanvasDoc.saveEligible,
  );

  let documentName = $derived(activeCanvasDoc ? activeCanvasDoc.title : "");

  let hasActiveCanvas = $derived(!!activeCanvasDoc);

  // -- callbacks --

  function handleCreateDocument(kind: DocumentKind): void {
    if (kind === "canvas") {
      topologyPickerOpen = true;
      topologyPickerStatus = "";
    } else if (kind === "simulation-report") {
      dashboardController.createDocument(kind);
    }
  }

  function handleTopologySelect(summary: GraphSummary): void {
    topologyPickerStatus = "";
    server.openGraph(summary.id, (reply) => {
      if (reply.status === "ok" && reply.graph) {
        dashboardController.openLoadedGraph(reply.graph);
        topologyPickerOpen = false;
      } else {
        topologyPickerStatus =
          reply.status === "not_found"
            ? "Topology not found."
            : "Failed to open topology.";
      }
    });
  }

  function handleSave(): void {
    const doc = activeCanvasDoc;
    if (!doc || !doc.saveEligible || isSaving) return;

    isSaving = true;
    server.saveGraph(doc.graph, (reply) => {
      isSaving = false;
      if (reply.status === "ok" && reply.graph) {
        doc.replaceFromSaveReply(reply.graph);
        statusMessage = "Saved.";
      } else if (reply.status === "stale") {
        statusMessage = "Save failed: graph was modified by another user.";
      } else if (reply.status === "not_found") {
        statusMessage = "Save failed: graph no longer exists.";
      } else {
        statusMessage = "Save failed.";
      }
    });
  }

  function handleForceParamsChange(change: Partial<ForceParams>): void {
    Object.assign(forceParams, change);
  }

  async function handleForceLayout(): Promise<void> {
    const doc = activeCanvasDoc;
    if (!doc) return;

    const { applyForceLayout } =
      await import("./dashboard/layout/ForceLayout.svelte");
    applyForceLayout(doc.graph.nodes, doc.graph.edges, forceParams);
    doc.graph = { ...doc.graph };
    fitToViewCounter++;
  }

  function handleRunSimulation(): void {
    const doc = activeCanvasDoc;
    if (!doc) {
      console.warn("Simulate ignored: no active canvas document");
      return;
    }
    if (!doc.loadedGraphId) {
      console.warn("Simulate ignored: canvas has no loadedGraphId");
      return;
    }

    console.log("Starting simulation for graph", doc.loadedGraphId, doc.title);
    dashboardController.runSimulationForGraph(doc.loadedGraphId, doc.title);
    server.runSimulation(doc.loadedGraphId);
  }

  function handleShowReport(): void {
    const canvasDocs = dashboardController.documents
      .filter((d) => d.kind === "canvas")
      .map((d) => d as CanvasDocument)
      .filter((d) => d.loadedGraphId)
      .map((d) => d.loadedGraphId!);

    if (canvasDocs.length === 0) return;

    simulationRunsStatus = "";
    simulationRunsModalOpen = true;

    server.fetchSimulationRuns(canvasDocs, (reply) => {
      simulationRuns = reply.runs;
      if (reply.runs.length === 0) {
        simulationRunsStatus = "No simulation runs found.";
      }
    });
  }

  function handleSimulationRunSelect(run: SimulationRunSummary): void {
    simulationRunsModalOpen = false;

    const existing = dashboardController.documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        (d as SimulationReportDocument).graphId === run.graph_id,
    ) as SimulationReportDocument | undefined;

    let report: SimulationReportDocument;

    if (existing) {
      report = existing;
    } else {
      report = new SimulationReportDocument(run.graph_title, run.graph_id);
      dashboardController.documents.push(report);
    }

    report.markReady(run.id);
    dashboardController.selectedDocumentId = report.id;

    server.fetchSimulationReport(run.id, run.graph_id, (data) => {
      report.setReportData(data);
    });
  }

  function applyCanvasSelection(
    doc: CanvasDocument,
    selection: CanvasSelection,
  ): void {
    switch (selection.kind) {
      case "node":
        doc.selectNode(selection.nodeId);
        break;
      case "edge":
        doc.selectEdge(selection.edgeId);
        break;
      default:
        doc.clearSelection();
    }
  }
</script>

<div class="dashboard-app" data-dashboard-theme="topology">
  <AppBar onSave={handleSave} {saveDisabled} {isSaving} />
  <DashboardRibbon
    {hasActiveCanvas}
    hasUnreadReport={dashboardController.hasUnreadReport}
    {forceParams}
    onForceParamsChange={handleForceParamsChange}
    onForceLayout={handleForceLayout}
    onRunSimulation={handleRunSimulation}
    onShowReport={handleShowReport}
  />

  {#snippet inspector()}
    <DashboardInspector document={dashboardController.activeDocument} />
  {/snippet}

  {#snippet content(document: WorkspaceDocument)}
    {#if document.kind === "canvas"}
      {@const canvasDoc = document as CanvasDocument}
      <Canvas
        graph={canvasDoc.graph}
        selection={canvasDoc.canvasSelection}
        onGraphChange={(g) => (canvasDoc.graph = g)}
        onSelectionChange={(sel) => applyCanvasSelection(canvasDoc, sel)}
        fitToViewRequested={fitToViewCounter}
      />
    {:else if document.kind === "simulation-report"}
      <SimulationReport document={document as SimulationReportDocument} />
    {/if}
  {/snippet}

  <Workspace
    documents={dashboardController.documents}
    activeDocumentId={dashboardController.selectedDocumentId}
    {documentTypes}
    onCreateDocument={handleCreateDocument}
    onActiveDocumentChange={(id) => {
      dashboardController.selectDocument(id);
      const doc = dashboardController.activeDocument;
      if (
        doc?.kind === "simulation-report" &&
        doc.status === "ready" &&
        doc.reportData === null &&
        doc.multiStateId
      ) {
        const reportDoc = doc as SimulationReportDocument;
        server.fetchSimulationReport(
          reportDoc.multiStateId!,
          reportDoc.graphId,
          (data) => {
            reportDoc.setReportData(data);
          },
        );
      }
    }}
    onCloseDocument={(id) => dashboardController.closeDocument(id)}
    {inspector}
    {content}
  />

  <TopologyPickerDialog
    open={topologyPickerOpen}
    summaries={graphSummaries}
    onOpenChange={(open) => (topologyPickerOpen = open)}
    onSelect={handleTopologySelect}
    status={topologyPickerStatus}
  />

  <SimulationRunsModal
    open={simulationRunsModalOpen}
    runs={simulationRuns}
    onOpenChange={(open) => (simulationRunsModalOpen = open)}
    onSelect={handleSimulationRunSelect}
    status={simulationRunsStatus}
  />

  <StatusBar {documentName} {statusMessage} />
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
