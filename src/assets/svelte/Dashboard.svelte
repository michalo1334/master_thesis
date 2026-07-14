<script lang="ts">
  import AppBar from "./dashboard/AppBar.svelte";
  import Ribbon from "./dashboard/Ribbon.svelte";
  import StatusBar from "./dashboard/StatusBar.svelte";
  import Workspace from "./dashboard/Workspace.svelte";
  import { dashboardDocuments, topologyNodes } from "./dashboard/data";
  import type { DashboardDocument, ViewMode } from "./dashboard/types";

  interface Props {
    projectName?: string;
    userName?: string;
  }

  let {
    projectName = "Production network topology",
    userName = "Aleksandra Nowak"
  }: Props = $props();

  const initialDocuments = dashboardDocuments.map((document) => ({ ...document }));

  let documents = $state<DashboardDocument[]>(initialDocuments);
  let activeDocumentId = $state(dashboardDocuments[0].id);
  let inspectorOpen = $state(true);
  let viewByDocument = $state<Record<string, ViewMode>>(
    Object.fromEntries(dashboardDocuments.map((document) => [document.id, "graph"]))
  );
  let selectionByDocument = $state<Record<string, string>>(
    Object.fromEntries(dashboardDocuments.map((document) => [document.id, document.initialSelectionId]))
  );
  let zoomByDocument = $state<Record<string, number>>(
    Object.fromEntries(dashboardDocuments.map((document) => [document.id, 100]))
  );

  let activeDocument = $derived(
    documents.find((document) => document.id === activeDocumentId) ?? documents[0]
  );
  let selectedNode = $derived(
    topologyNodes.find((node) => node.id === selectionByDocument[activeDocumentId]) ?? topologyNodes[0]
  );
  let activeView = $derived(viewByDocument[activeDocumentId] ?? "graph");
  let activeZoom = $derived(zoomByDocument[activeDocumentId] ?? 100);

  function activateDocument(id: string) {
    if (documents.some((document) => document.id === id)) activeDocumentId = id;
  }

  function closeDocument(id: string) {
    if (documents.length === 1) return;

    const closedIndex = documents.findIndex((document) => document.id === id);
    const wasActive = id === activeDocumentId;
    documents = documents.filter((document) => document.id !== id);

    if (wasActive) {
      activeDocumentId = documents[Math.min(closedIndex, documents.length - 1)].id;
    }
  }

  function selectNode(id: string) {
    selectionByDocument[activeDocumentId] = id;
  }

  function setView(view: ViewMode) {
    viewByDocument[activeDocumentId] = view;
  }

  function setZoom(value: number) {
    zoomByDocument[activeDocumentId] = Math.max(50, Math.min(180, value));
  }
</script>

<div class="dashboard-app" data-dashboard-theme="topology">
  <AppBar filename={activeDocument.title || projectName} {userName} />
  <Ribbon {activeView} onViewChange={setView} onToggleInspector={() => (inspectorOpen = !inspectorOpen)} />
  <Workspace
    {documents}
    {activeDocumentId}
    {activeDocument}
    {selectedNode}
    {activeView}
    {activeZoom}
    {inspectorOpen}
    onActivateDocument={activateDocument}
    onCloseDocument={closeDocument}
    onSelectNode={selectNode}
    onViewChange={setView}
    onZoomChange={setZoom}
    onCloseInspector={() => (inspectorOpen = false)}
    onRestoreInspector={() => (inspectorOpen = true)}
  />
  <StatusBar selectedName={selectedNode.name} zoom={activeZoom} />
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

  .dashboard-app :global(button:not(:disabled)) { cursor: pointer; }

  .dashboard-app :global(:focus-visible) {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 2px;
  }

  @media (max-width: 65.625em) {
    .dashboard-app {
      grid-template-rows:
        minmax(var(--ds-appbar-height), auto)
        minmax(var(--ds-ribbon-compact-height), auto)
        minmax(0, 1fr)
        minmax(var(--ds-statusbar-height), auto);
    }
  }

  @media (max-width: 47.5em) {
    .dashboard-app {
      grid-template-rows:
        minmax(var(--ds-appbar-height), auto)
        minmax(var(--ds-ribbon-mobile-height), auto)
        minmax(0, 1fr)
        minmax(var(--ds-statusbar-height), auto);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .dashboard-app :global(*),
    .dashboard-app :global(*::before),
    .dashboard-app :global(*::after) {
      scroll-behavior: auto !important;
      transition: none !important;
      animation: none !important;
    }
  }
</style>
