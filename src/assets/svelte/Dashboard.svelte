<script lang="ts">
  import type { Live } from "live_svelte";
  import { Dialog } from "bits-ui";
  import { onMount } from "svelte";
  import { dashboardDocuments } from "./dashboard/data";
  import AppBar from "./dashboard/shell/AppBar.svelte";
  import Button from "./dashboard/controls/Button.svelte";
  import Checkbox from "./dashboard/controls/Checkbox.svelte";
  import Icon from "./dashboard/controls/Icon.svelte";
  import RadioButton from "./dashboard/controls/RadioButton.svelte";
  import Ribbon from "./dashboard/ribbon/Ribbon";
  import Select from "./dashboard/controls/Select.svelte";
  import SplitButton from "./dashboard/controls/SplitButton.svelte";
  import Inspector from "./dashboard/workspace/Inspector.svelte";
  import StatusBar from "./dashboard/shell/StatusBar.svelte";
  import SimulationReport from "./dashboard/statistics/SimulationReport.svelte";
  import Workspace from "./dashboard/workspace/Workspace";
  import Canvas from "./dashboard/workspace/Canvas.svelte";
  import type { AssetKind } from "./dashboard/workspace/canvas/fixtures";

  type DocumentType = "topology" | "simulation";
  type TopologyLayout = "layered" | "force-directed" | "radial";
  type TopologyTool = "select" | "connect";

  interface SelectedTopologyObject {
    id: string;
    name: string;
  }

  interface WorkspaceDocument {
    id: string;
    title: string;
    type: DocumentType;
  }

  interface StoredWorkspace {
    documents: unknown[];
    activeDocumentId?: unknown;
    nextDocumentId?: unknown;
  }

  interface Props {
    live?: Live;
  }

  let { live }: Props = $props();

  const documentTypes = [
    { id: "topology", label: "Topology", icon: "graph" },
    { id: "simulation", label: "Simulation result", icon: "play" },
  ] as const;
  const workspaceStorageKey = "master-thesis.dashboard.workspace.v1";

  let documents = $state<WorkspaceDocument[]>([]);
  let activeDocumentId = $state<string>();
  let nextDocumentId = $state(1);
  let topologyDialogOpen = $state(false);
  let selectedTopologyId = $state<string>();
  let workspaceRestored = $state(false);
  let persistedWorkspace: string | undefined;
  let serializedWorkspace = $derived(
    JSON.stringify({ documents, activeDocumentId, nextDocumentId }),
  );
  let activeDocument = $derived(
    documents.find((document) => document.id === activeDocumentId),
  );
  let selectedTopology = $derived(
    dashboardDocuments.find((topology) => topology.id === selectedTopologyId),
  );
  let selectedObject = $state<SelectedTopologyObject>();
  let pendingAssetKind = $state<AssetKind>();
  let hasTopologyDocument = $derived(activeDocument?.type === "topology");
  let hasTopologySelection = $derived(
    hasTopologyDocument && selectedObject !== undefined,
  );
  let currentTool = $state<TopologyTool>("select");
  let topologyLayout = $state<TopologyLayout>("layered");
  let showZoneBoundaries = $state(true);
  let inspectorVisible = $state(true);
  let presentation = $state<"graph" | "list">("graph");
  $effect(() => {
    if (!workspaceRestored) return;

    const workspace = serializedWorkspace;
    if (workspace === persistedWorkspace) return;

    try {
      localStorage[workspaceStorageKey] = workspace;
    } catch {
      // Storage can be unavailable or full; retain the in-memory workspace.
    }
    persistedWorkspace = workspace;
  });

  onMount(() => {
    const workspaceWasNormalized = restoreWorkspace(localStorage);

    persistedWorkspace = serializedWorkspace;
    workspaceRestored = true;

    if (workspaceWasNormalized) persistWorkspace(persistedWorkspace);
  });

  function restoreWorkspace(storage: Storage) {
    let value: string | null;

    try {
      value = storage.getItem(workspaceStorageKey);
    } catch {
      return false;
    }

    if (value === null) return false;

    let storedWorkspace: StoredWorkspace;

    try {
      const parsedWorkspace: unknown = JSON.parse(value);
      if (!isStoredWorkspace(parsedWorkspace))
        throw new Error("Invalid workspace");
      storedWorkspace = parsedWorkspace;
    } catch {
      removeStoredWorkspace(storage);
      return false;
    }

    const restoredDocuments: WorkspaceDocument[] = [];
    const documentIds: string[] = [];
    let workspaceWasNormalized = false;

    for (const value of storedWorkspace.documents) {
      const document = parseWorkspaceDocument(value);

      if (!document || documentIds.includes(document.id)) {
        workspaceWasNormalized = true;
        continue;
      }

      documentIds.push(document.id);
      restoredDocuments.push(document);
    }

    const restoredActiveDocumentId =
      typeof storedWorkspace.activeDocumentId === "string" &&
      documentIds.includes(storedWorkspace.activeDocumentId)
        ? storedWorkspace.activeDocumentId
        : undefined;
    const restoredNextDocumentId = isAvailableNextDocumentId(
      storedWorkspace.nextDocumentId,
      restoredDocuments,
    )
      ? storedWorkspace.nextDocumentId
      : deriveNextDocumentId(restoredDocuments);

    if (
      storedWorkspace.activeDocumentId !== restoredActiveDocumentId ||
      storedWorkspace.nextDocumentId !== restoredNextDocumentId
    ) {
      workspaceWasNormalized = true;
    }

    documents = restoredDocuments;
    activeDocumentId = restoredActiveDocumentId;
    nextDocumentId = restoredNextDocumentId;

    return workspaceWasNormalized;
  }

  function isStoredWorkspace(value: unknown): value is StoredWorkspace {
    return (
      typeof value === "object" &&
      value !== null &&
      !Array.isArray(value) &&
      Array.isArray((value as StoredWorkspace).documents)
    );
  }

  function parseWorkspaceDocument(
    value: unknown,
  ): WorkspaceDocument | undefined {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      return undefined;
    }

    const { id, title, type } = value as Record<string, unknown>;

    if (
      typeof id !== "string" ||
      !id.trim() ||
      typeof title !== "string" ||
      !title.trim() ||
      (type !== "topology" && type !== "simulation")
    ) {
      return undefined;
    }

    return { id, title, type };
  }

  function isAvailableNextDocumentId(
    value: unknown,
    restoredDocuments: WorkspaceDocument[],
  ): value is number {
    return (
      typeof value === "number" &&
      Number.isSafeInteger(value) &&
      value > 0 &&
      !hasDocumentIdCollision(value, restoredDocuments)
    );
  }

  function deriveNextDocumentId(restoredDocuments: WorkspaceDocument[]) {
    let candidate = 1;

    while (hasDocumentIdCollision(candidate, restoredDocuments)) candidate += 1;

    return candidate;
  }

  function hasDocumentIdCollision(
    candidate: number,
    restoredDocuments: WorkspaceDocument[],
  ) {
    return restoredDocuments.some(
      (document) =>
        document.id === `topology-${candidate}` ||
        document.id === `simulation-${candidate}`,
    );
  }

  function serializeWorkspace() {
    return JSON.stringify({ documents, activeDocumentId, nextDocumentId });
  }

  function persistWorkspace(workspace: string) {
    try {
      localStorage.setItem(workspaceStorageKey, workspace);
    } catch {
      // Storage can be unavailable or full; retain the in-memory workspace.
    }
  }

  function onSave(): void {
    const workspace = serializeWorkspace();

    persistWorkspace(workspace);
    persistedWorkspace = workspace;
  }

  function removeStoredWorkspace(storage: Storage) {
    try {
      storage.removeItem(workspaceStorageKey);
    } catch {
      // Storage can be unavailable; leave the in-memory workspace unchanged.
    }
  }

  function setSelectedObject(object?: SelectedTopologyObject) {
    selectedObject = object;
  }

  function armAssetPlacement(kind: AssetKind) {
    if (!hasTopologyDocument) return;

    pendingAssetKind = kind;
    currentTool = "select";
  }

  function activateConnectTool() {
    if (!hasTopologyDocument) return;

    pendingAssetKind = undefined;
    currentTool = "connect";
  }

  function activateSelectTool() {
    if (!hasTopologyDocument) return;

    pendingAssetKind = undefined;
    currentTool = "select";
  }

  function setTopologyLayout(event: Event) {
    if (!hasTopologyDocument) return;

    topologyLayout = (event.currentTarget as HTMLSelectElement)
      .value as TopologyLayout;
  }

  function toggleZoneBoundaries() {
    if (!hasTopologyDocument) return;

    showZoneBoundaries = !showZoneBoundaries;
  }

  function removeSelection() {
    if (!hasTopologySelection) return;

    selectedObject = undefined;
  }

  function duplicateSelection() {}

  function lockSelection() {}

  function alignSelection() {}

  function runSimulation() {
    if (!hasTopologyDocument) return;

    live?.pushEvent("run_simulation", {
      document_id: activeDocument?.id,
      selected_object_id: selectedObject?.id,
      source: "ribbon",
    });
  }

  function optimizeDefense() {
    if (!hasTopologyDocument) return;

    live?.pushEvent("optimize_defense", {
      document_id: activeDocument?.id,
      selected_object_id: selectedObject?.id,
      source: "ribbon",
    });
  }

  function showGraph() {
    if (!hasTopologyDocument) return;

    presentation = "graph";
  }

  function showList() {
    if (!hasTopologyDocument) return;

    presentation = "list";
  }

  function toggleInspector() {
    inspectorVisible = !inspectorVisible;
  }

  function createDocument(typeId: string) {
    if (typeId === "topology") {
      selectedTopologyId = undefined;
      topologyDialogOpen = true;
      return;
    }

    const documentType = documentTypes.find(({ id }) => id === typeId);

    if (!documentType) return;

    const id = `${documentType.id}-${nextDocumentId++}`;
    const title = `${documentType.label} ${documents.filter((document) => document.type === documentType.id).length + 1}`;

    documents = [...documents, { id, title, type: documentType.id }];
    activeDocumentId = id;
  }

  function openSelectedTopology(): void {
    const topology = selectedTopology;

    if (!topology) return;

    const id = `topology-${nextDocumentId++}`;

    documents = [...documents, { id, title: topology.title, type: "topology" }];
    activeDocumentId = id;
    selectedObject = undefined;
    pendingAssetKind = undefined;
    selectedTopologyId = undefined;
    topologyDialogOpen = false;
  }

  function closeDocument(id: string) {
    const closedIndex = documents.findIndex((document) => document.id === id);
    const remainingDocuments = documents.filter(
      (document) => document.id !== id,
    );

    documents = remainingDocuments;

    if (activeDocumentId === id) {
      activeDocumentId =
        remainingDocuments[closedIndex]?.id ??
        remainingDocuments[closedIndex - 1]?.id;
    }
  }
</script>

<div class="dashboard-app" data-dashboard-theme="topology">
  <AppBar {onSave} />
  <Ribbon>
    <Ribbon.Tab title="Home">
      <Ribbon.Section title="Tools">
        <Button
          aria-pressed={currentTool === "select"}
          disabled={!hasTopologyDocument}
          onclick={activateSelectTool}
          ><Icon name="cursor" size={22} /><span>Select</span></Button
        >
        <Button
          aria-pressed={currentTool === "connect"}
          disabled={!hasTopologyDocument}
          onclick={activateConnectTool}
          ><Icon name="link" size={22} /><span>Connect</span></Button
        >
      </Ribbon.Section>
      <Ribbon.Section title="Add">
        <SplitButton
          items={[
            {
              label: "Server",
              icon: "server",
              disabled: !hasTopologyDocument,
              onclick: () => armAssetPlacement("Server"),
            },
            {
              label: "Workstation",
              icon: "server",
              disabled: !hasTopologyDocument,
              onclick: () => armAssetPlacement("Workstation"),
            },
            {
              label: "Firewall",
              icon: "shield",
              disabled: !hasTopologyDocument,
              onclick: () => armAssetPlacement("Firewall"),
            },
            {
              label: "Database",
              icon: "server",
              disabled: !hasTopologyDocument,
              onclick: () => armAssetPlacement("Database"),
            },
          ]}
          aria-label="Add server"
          aria-pressed={pendingAssetKind === "Server"}
          disabled={!hasTopologyDocument}
          onclick={() => armAssetPlacement("Server")}
        >
          <Icon name="server" size={22} /><span>Asset</span>
        </SplitButton>
        <Button><Icon name="zone" size={22} /><span>Zone</span></Button>
      </Ribbon.Section>
      <Ribbon.Section title="Layout">
        <Select
          label="Topology layout"
          value={topologyLayout}
          disabled={!hasTopologyDocument}
          onchange={setTopologyLayout}
        >
          <option value="layered">Layered</option>
          <option value="force-directed">Force-directed</option>
          <option value="radial">Radial</option>
        </Select>
      </Ribbon.Section>
      <Ribbon.Section title="Display">
        <Checkbox
          checked={showZoneBoundaries}
          disabled={!hasTopologyDocument}
          onchange={toggleZoneBoundaries}>Show zone boundaries</Checkbox
        >
      </Ribbon.Section>
      <Ribbon.Section title="Arrange">
        <Button
          variant="small"
          disabled={!hasTopologySelection}
          onclick={duplicateSelection}
          ><Icon name="copy" size={16} /><span>Duplicate</span></Button
        >
        <Button
          variant="small"
          disabled={!hasTopologySelection}
          onclick={removeSelection}
          ><Icon name="trash" size={16} /><span>Remove</span></Button
        >
        <Button
          variant="small"
          disabled={!hasTopologySelection}
          onclick={lockSelection}
          ><Icon name="lock" size={16} /><span>Lock</span></Button
        >
        <Button
          variant="small"
          disabled={!hasTopologySelection}
          onclick={alignSelection}
          ><Icon name="align" size={16} /><span>Align</span></Button
        >
      </Ribbon.Section>
      <Ribbon.Section title="Security">
        <Button><Icon name="shield" size={22} /><span>Defense</span></Button>
        <Button><Icon name="tag" size={22} /><span>Classify</span></Button>
      </Ribbon.Section>
    </Ribbon.Tab>
    <Ribbon.Tab title="Insert">
      <Ribbon.Section title="Topology">
        <Button
          aria-pressed={pendingAssetKind === "Server"}
          disabled={!hasTopologyDocument}
          onclick={() => armAssetPlacement("Server")}
          ><Icon name="server" size={22} /><span>Server</span></Button
        >
        <Button disabled
          ><Icon name="zone" size={22} /><span>Gateway</span></Button
        >
        <Button
          aria-pressed={currentTool === "connect"}
          disabled={!hasTopologyDocument}
          onclick={activateConnectTool}
          ><Icon name="link" size={22} /><span>Trust link</span></Button
        >
      </Ribbon.Section>
    </Ribbon.Tab>
    <Ribbon.Tab title="Analyze">
      <Ribbon.Section title="Attack model">
        <Button disabled={!hasTopologyDocument} onclick={runSimulation}
          ><Icon name="play" size={22} /><span>Simulate</span></Button
        >
        <Button disabled={!hasTopologyDocument} onclick={optimizeDefense}
          ><Icon name="shield" size={22} /><span>Optimize</span></Button
        >
      </Ribbon.Section>
    </Ribbon.Tab>
    <Ribbon.Tab title="View">
      <Ribbon.Section title="Presentation">
        <RadioButton
          name="presentation"
          checked={presentation === "graph"}
          disabled={!hasTopologyDocument}
          onchange={showGraph}><Icon name="graph" size={16} />Graph</RadioButton
        >
        <RadioButton
          name="presentation"
          checked={presentation === "list"}
          disabled={!hasTopologyDocument}
          onchange={showList}><Icon name="list" size={16} />List</RadioButton
        >
        <Button aria-pressed={inspectorVisible} onclick={toggleInspector}
          ><Icon name="chevron-right" size={22} /><span>Inspector</span></Button
        >
      </Ribbon.Section>
    </Ribbon.Tab>
  </Ribbon>
  {#snippet inspector()}
    {#if inspectorVisible}
      <Inspector title="Object inspector">
        <p class="dashboard-inspector-empty">
          {selectedObject
            ? selectedObject.name
            : "The active canvas has no selected objects."}
        </p>
      </Inspector>
    {/if}
  {/snippet}
  <Workspace
    {activeDocumentId}
    orientation="vertical"
    onActiveDocumentChange={(id) => (activeDocumentId = id)}
    onCloseDocument={closeDocument}
    {documentTypes}
    onCreateDocument={createDocument}
    {inspector}
  >
    {#each documents as document (document.id)}
      <Workspace.Document id={document.id} title={document.title}>
        {#if document.type === "simulation"}
          <SimulationReport title={document.title} />
        {:else}
          <Canvas
            tool={currentTool}
            placementKind={pendingAssetKind}
            onPlacementConsumed={() => (pendingAssetKind = undefined)}
            onSelectionChange={setSelectedObject}
            onEdgeCreated={() => (currentTool = "select")}
          />
        {/if}
      </Workspace.Document>
    {/each}
  </Workspace>
  <Dialog.Root bind:open={topologyDialogOpen}>
    <Dialog.Portal>
      <Dialog.Overlay class="dashboard-topology-dialog-overlay" />
      <Dialog.Content class="dashboard-topology-dialog-content">
        <Dialog.Title class="dashboard-topology-dialog-title"
          >Topology</Dialog.Title
        >
        <fieldset class="dashboard-topology-dialog-options">
          <legend class="dashboard-topology-dialog-legend"
            >Choose a topology</legend
          >
          {#each dashboardDocuments as topology (topology.id)}
            <label
              class={[
                "dashboard-topology-dialog-option",
                selectedTopologyId === topology.id &&
                  "dashboard-topology-dialog-option-selected",
              ]}
            >
              <input
                type="radio"
                name="topology-document"
                value={topology.id}
                bind:group={selectedTopologyId}
              />
              <span class="dashboard-topology-dialog-option-copy">
                <span class="dashboard-topology-dialog-option-title"
                  >{topology.title}</span
                >
                <span class="dashboard-topology-dialog-option-kind"
                  >{topology.kind}</span
                >
              </span>
            </label>
          {/each}
        </fieldset>
        <div class="dashboard-topology-dialog-actions">
          <Dialog.Close class="dashboard-topology-dialog-close" type="button"
            >Close</Dialog.Close
          >
          <button
            class="dashboard-topology-dialog-open"
            type="button"
            disabled={!selectedTopology}
            onclick={openSelectedTopology}>Open</button
          >
        </div>
      </Dialog.Content>
    </Dialog.Portal>
  </Dialog.Root>
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

  :global(.dashboard-document-placeholder) {
    height: 100%;
    padding: 2rem;
    color: var(--ds-color-text-secondary);
    background: var(--ds-color-surface);
  }

  :global(.dashboard-document-placeholder h1),
  :global(.dashboard-document-placeholder p) {
    margin: 0;
  }

  :global(.dashboard-document-placeholder p) {
    margin-top: var(--ds-space-2);
  }

  .dashboard-inspector-empty {
    margin: 0;
    color: var(--ds-color-text-faint);
  }

  :global(.dashboard-topology-dialog-overlay) {
    position: fixed;
    z-index: 200;
    inset: 0;
    background: rgb(14 26 43 / 50%);
  }

  :global(.dashboard-topology-dialog-content) {
    position: fixed;
    z-index: 201;
    top: 50%;
    left: 50%;
    width: min(32rem, calc(100vw - 2rem));
    max-height: calc(100dvh - 2rem);
    overflow-y: auto;
    padding: var(--ds-space-4);
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
    transform: translate(-50%, -50%);
  }

  :global(.dashboard-topology-dialog-title) {
    margin: 0;
    color: var(--ds-color-text);
    font-size: var(--ds-text-xl);
  }

  :global(.dashboard-topology-dialog-options) {
    display: grid;
    gap: var(--ds-space-2);
    margin: var(--ds-space-4) 0;
    padding: 0;
    border: 0;
  }

  :global(.dashboard-topology-dialog-legend) {
    padding: 0;
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
    font-weight: 600;
  }

  :global(.dashboard-topology-dialog-option) {
    display: flex;
    align-items: center;
    gap: var(--ds-space-3);
    padding: var(--ds-space-3);
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-surface);
  }

  :global(.dashboard-topology-dialog-option:hover) {
    background: var(--ds-color-accent-soft);
  }

  :global(.dashboard-topology-dialog-option-selected) {
    border-color: var(--ds-color-focus);
    background: var(--ds-color-accent-soft);
  }

  :global(.dashboard-topology-dialog-option input) {
    flex: none;
    margin: 0;
    accent-color: var(--ds-color-focus);
  }

  :global(.dashboard-topology-dialog-option-copy) {
    min-width: 0;
    display: grid;
    gap: 0.125rem;
  }

  :global(.dashboard-topology-dialog-option-title) {
    color: var(--ds-color-text);
    font-weight: 600;
  }

  :global(.dashboard-topology-dialog-option-kind) {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
    text-transform: capitalize;
  }

  :global(.dashboard-topology-dialog-actions) {
    display: flex;
    justify-content: flex-end;
    gap: var(--ds-space-2);
  }

  :global(.dashboard-topology-dialog-close) {
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-sm);
    color: var(--ds-color-text);
    background: var(--ds-color-surface);
  }

  :global(.dashboard-topology-dialog-close:hover) {
    background: var(--ds-color-accent-soft);
  }

  :global(.dashboard-topology-dialog-open) {
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ds-color-focus);
    border-radius: var(--ds-radius-sm);
    color: var(--ds-color-on-dark);
    background: var(--ds-color-focus);
  }

  :global(.dashboard-topology-dialog-open:disabled) {
    opacity: 0.55;
  }

  :global(.dashboard-topology-dialog-open:not(:disabled):hover) {
    filter: brightness(0.95);
  }

  @media (max-width: 30rem) {
    :global(.dashboard-topology-dialog-content) {
      width: calc(100vw - 1rem);
      max-height: calc(100dvh - 1rem);
      padding: var(--ds-space-3);
    }

    :global(.dashboard-topology-dialog-actions) {
      flex-direction: column-reverse;
    }

    :global(.dashboard-topology-dialog-close),
    :global(.dashboard-topology-dialog-open) {
      width: 100%;
    }
  }
</style>
