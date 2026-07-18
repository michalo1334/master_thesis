<script lang="ts">
  import { onMount } from "svelte";
  import type { Live } from "live_svelte";
  import AppBar from "./dashboard/shell/AppBar.svelte";
  import StatusBar from "./dashboard/shell/StatusBar.svelte";
  import DashboardInspector from "./dashboard/DashboardInspector.svelte";
  import DashboardRibbon from "./dashboard/DashboardRibbon.svelte";
  import SimulationReport from "./dashboard/statistics/SimulationReport.svelte";
  import Canvas from "./dashboard/workspace/Canvas.svelte";
  import Workspace, {
    type WorkspaceDocumentType,
  } from "./dashboard/workspace/Workspace.svelte";
  import {
    topologyEditableStateKey,
    topologyFromSuccessfulSaveReply,
    topologySavePayload,
    type ServerGraphSummary,
    type ServerTopologyGraph,
    type TopologySaveReply,
    type TopologyDocument,
    type TopologyEditorState,
    type WorkspaceDocument,
  } from "./dashboard/workspace/model";
  import {
    parseWorkspace,
    serializeWorkspace,
  } from "./dashboard/workspace/persistence";
  import { WorkspaceState } from "./dashboard/workspace/state.svelte";
  import TopologyPickerDialog from "./dashboard/workspace/TopologyPickerDialog.svelte";

  interface Props {
    live?: Live;
    graphSummaries?: readonly ServerGraphSummary[];
  }

  let { live, graphSummaries = [] }: Props = $props();

  const documentTypes = [
    { id: "topology", label: "Topology", icon: "graph" },
    { id: "simulation", label: "Simulation result", icon: "play" },
  ] as const satisfies readonly WorkspaceDocumentType[];
  const workspaceStorageKey = "master-thesis.dashboard.workspace.v1";

  const workspace = new WorkspaceState();
  let inspectorVisible = $state(true);
  let topologyPickerOpen = $state(false);
  let isSaving = $state(false);
  let saveStatusMessage = $state<string>();

  onMount(() => {
    restoreWorkspace(localStorage);
  });

  function restoreWorkspace(storage: Storage) {
    let value: string | null;

    try {
      value = storage.getItem(workspaceStorageKey);
    } catch {
      return;
    }

    if (value === null) return;

    const restored = parseWorkspace(value);
    if (!restored) {
      removeStoredWorkspace(storage);
      return;
    }

    workspace.restore(restored);
  }

  function persistWorkspace(workspace: string) {
    try {
      localStorage.setItem(workspaceStorageKey, workspace);
    } catch {
      // Storage can be unavailable or full; retain the in-memory workspace.
    }
  }

  function persistCurrentWorkspace() {
    persistWorkspace(serializeWorkspace(workspace.snapshot()));
  }

  function removeStoredWorkspace(storage: Storage) {
    try {
      storage.removeItem(workspaceStorageKey);
    } catch {
      // Storage can be unavailable; leave the in-memory workspace unchanged.
    }
  }

  function onSave() {
    persistCurrentWorkspace();

    if (isSaving || !workspace.activeTopology || !live) return;

    const savingDocument = workspace.activeTopology;
    const submittedStateKey = topologyEditableStateKey(savingDocument.graph);
    saveStatusMessage = undefined;
    isSaving = true;

    try {
      live.pushEvent(
        "save_topology",
        topologySavePayload(savingDocument.graph),
        (reply) => {
          try {
            const savingDocumentIsOpen = workspace.documents.some(
              (document) =>
                document.type === "topology" &&
                document.id === savingDocument.id &&
                document.graph.id === savingDocument.graph.id,
            );
            if (!savingDocumentIsOpen) return;

            const saveReply = reply as TopologySaveReply;
            const topology = topologyFromSuccessfulSaveReply(saveReply);
            if (topology) {
              workspace.applySavedTopology(
                savingDocument.id,
                topology,
                submittedStateKey,
              );
              persistCurrentWorkspace();
              saveStatusMessage = "Saved";
              return;
            }

            saveStatusMessage =
              saveReply.status === "stale" || saveReply.stale === true
                ? "Save conflict: local changes were kept. Reopen the topology before retrying."
                : "Save failed; local changes kept";
          } finally {
            isSaving = false;
          }
        },
      );
    } catch {
      isSaving = false;
      saveStatusMessage = "Save failed; local changes kept";
    }
  }

  function createDocument(typeId: string) {
    if (typeId === "topology") {
      topologyPickerOpen = true;
      return;
    }

    if (typeId !== "simulation") return;

    workspace.createSimulationDocument();
    persistCurrentWorkspace();
  }

  function openTopology(graph: ServerGraphSummary) {
    topologyPickerOpen = false;
    live?.pushEvent("open_topology", { graph_id: graph.id }, (reply) => {
      const { topology } = reply as { topology?: ServerTopologyGraph };
      if (!topology) return;

      workspace.openTopology(topology);
      persistCurrentWorkspace();
    });
  }

  function updateTopologyDocument(
    id: string,
    change: Pick<TopologyDocument, "graph"> | Pick<TopologyDocument, "editor">,
  ) {
    workspace.updateTopologyDocument(id, change);
    if ("graph" in change) saveStatusMessage = undefined;
    persistCurrentWorkspace();
  }

  function closeDocument(id: string) {
    workspace.closeDocument(id);
    persistCurrentWorkspace();
  }

  function activateDocument(id: string) {
    workspace.activeDocumentId = id;
    saveStatusMessage = undefined;
    persistCurrentWorkspace();
  }

  function runSimulation() {
    if (!workspace.activeTopology) return;

    live?.pushEvent("run_simulation", {
      graph_id: workspace.activeTopology.graph.id,
      selected_object_id: workspace.selectedObject?.id,
      source: "ribbon",
    });
  }

  function optimizeDefense() {
    if (!workspace.activeTopology) return;

    live?.pushEvent("optimize_defense", {
      graph_id: workspace.activeTopology.graph.id,
      selected_object_id: workspace.selectedObject?.id,
      source: "ribbon",
    });
  }

  function updateActiveEditor(editor: TopologyEditorState) {
    if (workspace.activeTopology)
      updateTopologyDocument(workspace.activeTopology.id, { editor });
  }
</script>

<div class="dashboard-app" data-dashboard-theme="topology">
  <AppBar {onSave} {isSaving} />
  <DashboardRibbon
    topology={workspace.activeTopology}
    {inspectorVisible}
    onEditorChange={updateActiveEditor}
    onInspectorToggle={() => (inspectorVisible = !inspectorVisible)}
    {runSimulation}
    {optimizeDefense}
  />

  {#snippet documentContent(document: WorkspaceDocument)}
    {#if document.type === "simulation"}
      <SimulationReport title={document.title} />
    {:else}
      <Canvas
        graph={document.graph}
        editor={document.editor}
        onGraphChange={(graph) =>
          updateTopologyDocument(document.id, { graph })}
        onEditorChange={(editor) =>
          updateTopologyDocument(document.id, { editor })}
      />
    {/if}
  {/snippet}

  {#snippet inspector()}
    <DashboardInspector selectedObject={workspace.selectedObject} />
  {/snippet}

  <Workspace
    documents={workspace.documents}
    activeDocumentId={workspace.activeDocumentId}
    orientation="vertical"
    onActiveDocumentChange={activateDocument}
    onCloseDocument={closeDocument}
    {documentTypes}
    onCreateDocument={createDocument}
    inspector={inspectorVisible ? inspector : undefined}
    content={documentContent}
  />
  <TopologyPickerDialog
    {graphSummaries}
    open={topologyPickerOpen}
    onOpenChange={(open) => (topologyPickerOpen = open)}
    onSelect={openTopology}
  />

  <StatusBar
    documentName={workspace.activeDocument?.title ?? "No document"}
    statusMessage={workspace.activeTopologyDirty
      ? (saveStatusMessage ?? "Unsaved changes")
      : saveStatusMessage}
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
