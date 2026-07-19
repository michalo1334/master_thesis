<script lang="ts">
  import type { Live } from "live_svelte";
  import { DashboardController } from "./dashboard/DashboardController.svelte";
  import { setDashboardContext } from "./dashboard/dashboard-context";
  import { createDashboardServer, type LiveServer } from "./dashboard/server";
  import AppBar from "./dashboard/shell/AppBar.svelte";
  import StatusBar from "./dashboard/shell/StatusBar.svelte";
  import DashboardInspector from "./dashboard/DashboardInspector.svelte";
  import DashboardRibbon from "./dashboard/DashboardRibbon.svelte";
  import Workspace from "./dashboard/workspace/Workspace.svelte";
  import TopologyPickerDialog from "./dashboard/workspace/TopologyPickerDialog.svelte";
  import Canvas from "./dashboard/canvas/Canvas.svelte";
  import SimulationReport from "./dashboard/simulation/SimulationReport.svelte";
  import type {
    WorkspaceDocument,
    DocumentKind,
  } from "./dashboard/workspace/WorkspaceDocument.svelte";
  import type {
    CanvasDocument,
    CanvasSelection,
  } from "./dashboard/workspace/CanvasDocument.svelte";
  import type { WorkspaceDocumentType } from "./dashboard/workspace/Workspace.svelte";
  import type { GraphSummary } from "./dashboard/contract";

  interface Props {
    live: Live;
    graphSummaries?: GraphSummary[];
  }

  const { live, graphSummaries = [] }: Props = $props();

  const dashboardController = new DashboardController();
  const server = $derived(createDashboardServer(live as LiveServer));

  setDashboardContext(dashboardController);

  const documentTypes: readonly WorkspaceDocumentType[] = [
    { id: "canvas", label: "Canvas", icon: "graph" },
    { id: "simulation-report", label: "Report", icon: "shield" },
  ];

  // -- dialog state --
  let topologyPickerOpen = $state(false);
  let topologyPickerStatus = $state("");

  // -- save state --
  let isSaving = $state(false);
  let statusMessage = $state("");

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

  // -- callbacks --

  function handleCreateDocument(kind: DocumentKind): void {
    if (kind === "canvas") {
      // Canvas menu opens the topology picker, not a blank tab.
      topologyPickerOpen = true;
      topologyPickerStatus = "";
    } else {
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
  <DashboardRibbon inspectorVisible={true} />

  {#snippet inspector()}
    <DashboardInspector document={dashboardController.activeDocument} />
  {/snippet}

  {#snippet content(document: WorkspaceDocument)}
    {#if document.kind === "canvas"}
      <Canvas
        graph={document.graph}
        selection={document.selection}
        onGraphChange={(g) => (document.graph = g)}
        onSelectionChange={(sel) => applyCanvasSelection(document, sel)}
      />
    {:else if document.kind === "simulation-report"}
      <SimulationReport title={document.title} />
    {/if}
  {/snippet}

  <Workspace
    documents={dashboardController.documents}
    activeDocumentId={dashboardController.selectedDocumentId}
    {documentTypes}
    onCreateDocument={handleCreateDocument}
    onActiveDocumentChange={(id) => dashboardController.selectDocument(id)}
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
