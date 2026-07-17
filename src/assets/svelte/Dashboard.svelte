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
  import { createDemoTopologyGraph } from "./dashboard/workspace/demo-graph";
  import {
    createSimulationDocument,
    createTopologyDocument,
    graphNodeLabel,
    graphTypeLabel,
    nextActiveDocumentId,
    type TopologyDocument,
    type TopologyEditorState,
    type WorkspaceDocument,
  } from "./dashboard/workspace/model";
  import {
    parseWorkspace,
    serializeWorkspace,
  } from "./dashboard/workspace/persistence";

  interface Props {
    live?: Live;
  }

  let { live }: Props = $props();

  const documentTypes = [
    { id: "topology", label: "Topology", icon: "graph" },
    { id: "simulation", label: "Simulation result", icon: "play" },
  ] as const satisfies readonly WorkspaceDocumentType[];
  const workspaceStorageKey = "master-thesis.dashboard.workspace.v1";

  let documents = $state<WorkspaceDocument[]>([]);
  let activeDocumentId = $state<string>();
  let nextDocumentId = $state(1);
  let inspectorVisible = $state(true);
  let workspaceRestored = $state(false);
  let persistedWorkspace: string | undefined;
  let activeDocument = $derived(
    documents.find((document) => document.id === activeDocumentId),
  );
  let activeTopology = $derived(
    activeDocument?.type === "topology" ? activeDocument : undefined,
  );
  let selectedObject = $derived.by(() =>
    selectedTopologyObject(activeTopology),
  );
  let serializedWorkspace = $derived(
    serializeWorkspace({ documents, activeDocumentId, nextDocumentId }),
  );

  $effect(() => {
    if (!workspaceRestored || serializedWorkspace === persistedWorkspace)
      return;

    try {
      localStorage.setItem(workspaceStorageKey, serializedWorkspace);
    } catch {
      // Storage can be unavailable or full; retain the in-memory workspace.
    }
    persistedWorkspace = serializedWorkspace;
  });

  onMount(() => {
    restoreWorkspace(localStorage);
    persistedWorkspace = serializedWorkspace;
    workspaceRestored = true;
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

    documents = restored.documents;
    activeDocumentId = restored.activeDocumentId;
    nextDocumentId = restored.nextDocumentId;
  }

  function persistWorkspace(workspace: string) {
    try {
      localStorage.setItem(workspaceStorageKey, workspace);
    } catch {
      // Storage can be unavailable or full; retain the in-memory workspace.
    }
  }

  function removeStoredWorkspace(storage: Storage) {
    try {
      storage.removeItem(workspaceStorageKey);
    } catch {
      // Storage can be unavailable; leave the in-memory workspace unchanged.
    }
  }

  function onSave() {
    const workspace = serializeWorkspace({
      documents,
      activeDocumentId,
      nextDocumentId,
    });
    persistWorkspace(workspace);
    persistedWorkspace = workspace;
  }

  function selectedTopologyObject(document?: TopologyDocument) {
    const selectedId = document?.editor.selectedId;
    if (!document || !selectedId) return undefined;

    const node = document.graph.nodes.find(
      (candidate) => candidate.id === selectedId,
    );
    if (node) return { id: node.id, name: graphNodeLabel(node) };

    const edge = document.graph.edges.find(
      (candidate) => candidate.id === selectedId,
    );
    if (!edge) return undefined;

    const source = document.graph.nodes.find((node) => node.id === edge.fromId);
    const target = document.graph.nodes.find((node) => node.id === edge.toId);
    return {
      id: edge.id,
      name:
        source && target
          ? `${graphNodeLabel(source)} → ${graphNodeLabel(target)} (${graphTypeLabel(edge.type)})`
          : graphTypeLabel(edge.type),
    };
  }

  function createDocument(typeId: string) {
    if (typeId === "topology") {
      const id = `topology-${nextDocumentId++}`;
      const title = `Topology ${documents.filter((document) => document.type === "topology").length + 1}`;
      documents = [
        ...documents,
        createTopologyDocument(id, title, createDemoTopologyGraph(id)),
      ];
      activeDocumentId = id;
      return;
    }

    if (typeId !== "simulation") return;

    const id = `simulation-${nextDocumentId++}`;
    const title = `Simulation result ${documents.filter((document) => document.type === "simulation").length + 1}`;
    documents = [...documents, createSimulationDocument(id, title)];
    activeDocumentId = id;
  }

  function updateTopologyDocument(
    id: string,
    change: Pick<TopologyDocument, "graph"> | Pick<TopologyDocument, "editor">,
  ) {
    documents = documents.map((document) =>
      document.type === "topology" && document.id === id
        ? { ...document, ...change }
        : document,
    );
  }

  function closeDocument(id: string) {
    activeDocumentId = nextActiveDocumentId(documents, activeDocumentId, id);
    documents = documents.filter((document) => document.id !== id);
  }

  function runSimulation() {
    if (!activeTopology) return;

    live?.pushEvent("run_simulation", {
      document_id: activeTopology.id,
      selected_object_id: selectedObject?.id,
      source: "ribbon",
    });
  }

  function optimizeDefense() {
    if (!activeTopology) return;

    live?.pushEvent("optimize_defense", {
      document_id: activeTopology.id,
      selected_object_id: selectedObject?.id,
      source: "ribbon",
    });
  }

  function updateActiveEditor(editor: TopologyEditorState) {
    if (activeTopology) updateTopologyDocument(activeTopology.id, { editor });
  }
</script>

<div class="dashboard-app" data-dashboard-theme="topology">
  <AppBar {onSave} />
  <DashboardRibbon
    topology={activeTopology}
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
    <DashboardInspector {selectedObject} />
  {/snippet}

  <Workspace
    {documents}
    {activeDocumentId}
    orientation="vertical"
    onActiveDocumentChange={(id) => (activeDocumentId = id)}
    onCloseDocument={closeDocument}
    {documentTypes}
    onCreateDocument={createDocument}
    inspector={inspectorVisible ? inspector : undefined}
    content={documentContent}
  />

  <StatusBar documentName={activeDocument?.title ?? "No document"} />
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
