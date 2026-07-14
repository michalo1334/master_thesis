<script lang="ts">
  import { Tabs } from "bits-ui";
  import DocumentTabs from "./DocumentTabs.svelte";
  import PropertyInspector from "./PropertyInspector.svelte";
  import TopologyCanvas from "./TopologyCanvas.svelte";
  import type { DashboardDocument, TopologyNode, ViewMode } from "./types";

  interface Props {
    documents: DashboardDocument[];
    activeDocumentId: string;
    activeDocument: DashboardDocument;
    selectedNode: TopologyNode;
    activeView: ViewMode;
    activeZoom: number;
    inspectorOpen: boolean;
    onActivateDocument: (id: string) => void;
    onCloseDocument: (id: string) => void;
    onSelectNode: (id: string) => void;
    onViewChange: (view: ViewMode) => void;
    onZoomChange: (zoom: number) => void;
    onCloseInspector: () => void;
    onRestoreInspector: () => void;
  }

  let {
    documents, activeDocumentId, activeDocument, selectedNode, activeView, activeZoom,
    inspectorOpen, onActivateDocument, onCloseDocument, onSelectNode, onViewChange,
    onZoomChange, onCloseInspector, onRestoreInspector
  }: Props = $props();
</script>

<main class={["dashboard-workspace", !inspectorOpen && "inspector-collapsed"]}>
  <Tabs.Root
    class="dashboard-document"
    value={activeDocumentId}
    onValueChange={onActivateDocument}
    loop
    activationMode="automatic"
  >
    <DocumentTabs {documents} onClose={onCloseDocument} />
    {#each documents as document (document.id)}
      <Tabs.Content class="dashboard-document-panel" value={document.id}>
        {#if document.id === activeDocumentId}
          <TopologyCanvas
            document={activeDocument}
            selectedNodeId={selectedNode.id}
            view={activeView}
            zoom={activeZoom}
            {inspectorOpen}
            {onSelectNode}
            {onViewChange}
            {onZoomChange}
            {onRestoreInspector}
          />
        {/if}
      </Tabs.Content>
    {/each}
  </Tabs.Root>
  {#if inspectorOpen}
    <PropertyInspector node={selectedNode} onClose={onCloseInspector} />
  {/if}
</main>

<style>
  .dashboard-workspace {
    grid-area: workspace;
    position: relative;
    display: grid;
    grid-template:
      "document inspector" minmax(0, 1fr)
      / minmax(0, 1fr) var(--ds-inspector-width);
    min-width: 0;
    min-height: 0;
  }

  .dashboard-workspace.inspector-collapsed {
    grid-template:
      "document" minmax(0, 1fr)
      / minmax(0, 1fr);
  }

  /* Bits UI renders the document root and panels inside this local workspace. */
  .dashboard-workspace :global(.dashboard-document) {
    grid-area: document;
    display: grid;
    grid-template-rows: var(--ds-document-tabs-height) minmax(0, 1fr);
    min-width: 0;
    min-height: 0;
  }

  .dashboard-workspace :global(.dashboard-document-panel) { min-width: 0; min-height: 0; }

  @media (max-width: 65.625em) {
    .dashboard-workspace { grid-template-columns: minmax(0, 1fr) var(--ds-inspector-compact-width); }
  }

  @media (max-width: 47.5em) {
    .dashboard-workspace,
    .dashboard-workspace.inspector-collapsed {
      grid-template: "document" minmax(0, 1fr) / minmax(0, 1fr);
    }
  }
</style>
