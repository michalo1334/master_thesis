<script lang="ts">
  import type { Live } from "live_svelte";
  import { onMount } from "svelte";
  import { SvelteSet } from "svelte/reactivity";
  import AppBar from "./dashboard/shell/AppBar.svelte";
  import {
    commandAvailable,
    executeCommand,
    type CommandContext,
    type CommandId,
    type DashboardUiState,
    type SelectedTopologyObject,
    type TopologyLayout,
  } from "./dashboard/commands/registry";
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

  interface ServerCommand {
    version: number;
    command: string;
    documentId?: string;
    title?: string;
    message: string;
  }

  interface Props {
    live?: Live;
    serverCommand?: ServerCommand;
  }

  let { live, serverCommand }: Props = $props();

  const documentTypes = [
    { id: "topology", label: "Topology", icon: "graph" },
    { id: "simulation", label: "Simulation result", icon: "play" },
  ] as const;
  const workspaceStorageKey = "master-thesis.dashboard.workspace.v1";

  let documents = $state<WorkspaceDocument[]>([]);
  let activeDocumentId = $state<string>();
  let nextDocumentId = $state(1);
  let workspaceRestored = $state(false);
  let persistedWorkspace: string | undefined;
  let serializedWorkspace = $derived(
    JSON.stringify({ documents, activeDocumentId, nextDocumentId }),
  );
  let activeDocument = $derived(
    documents.find((document) => document.id === activeDocumentId),
  );
  let selectedObject = $state<SelectedTopologyObject>();
  let pendingAssetKind = $state<AssetKind>();
  let serverStatus = $derived(serverCommand?.message);
  let canEditTopology = $derived(activeDocument?.type === "topology");
  let ui = $state<DashboardUiState>({
    currentTool: "select",
    topologyLayout: "layered",
    showZoneBoundaries: true,
    inspectorVisible: true,
    presentation: "graph",
  });
  const reconciledServerCommandVersions = new SvelteSet<number>();
  let commandContext = $derived.by(() => ({
    activeDocument,
    selectedObject,
    ui: {
      currentTool: ui.currentTool,
      topologyLayout: ui.topologyLayout,
      showZoneBoundaries: ui.showZoneBoundaries,
      inspectorVisible: ui.inspectorVisible,
      presentation: ui.presentation,
      lastSelectionAction: ui.lastSelectionAction,
    },
    live,
    setUi: updateUi,
    setSelectedObject,
  }));

  $effect(reconcileServerCommand);

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
    const documentIds = new SvelteSet<string>();
    let workspaceWasNormalized = false;

    for (const value of storedWorkspace.documents) {
      const document = parseWorkspaceDocument(value);

      if (!document || documentIds.has(document.id)) {
        workspaceWasNormalized = true;
        continue;
      }

      documentIds.add(document.id);
      restoredDocuments.push(document);
    }

    const restoredActiveDocumentId =
      typeof storedWorkspace.activeDocumentId === "string" &&
      documentIds.has(storedWorkspace.activeDocumentId)
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

  function removeStoredWorkspace(storage: Storage) {
    try {
      storage.removeItem(workspaceStorageKey);
    } catch {
      // Storage can be unavailable; leave the in-memory workspace unchanged.
    }
  }

  function reconcileServerCommand() {
    const command = serverCommand;

    if (!command) return;
    if (reconciledServerCommandVersions.has(command.version)) return;

    reconciledServerCommandVersions.add(command.version);
    if (command.command !== "run_simulation") return;

    const id = command.documentId ?? `simulation-${command.version}`;
    const existingDocument = documents.find((document) => document.id === id);
    const title =
      command.title ?? existingDocument?.title ?? "Simulation result";

    documents = existingDocument
      ? documents.map((document) =>
          document.id === id ? { ...document, title } : document,
        )
      : [...documents, { id, title, type: "simulation" }];
    activeDocumentId = id;
  }

  function updateUi(update: Partial<DashboardUiState>) {
    Object.assign(ui, update);
  }

  function setSelectedObject(object?: SelectedTopologyObject) {
    selectedObject = object;
  }

  function armAssetPlacement(kind: AssetKind) {
    pendingAssetKind = kind;
    updateUi({ currentTool: "select" });
  }

  function activateConnectTool() {
    pendingAssetKind = undefined;
    execute("connect-tool", "ribbon");
  }

  function activateSelectTool() {
    pendingAssetKind = undefined;
    execute("select-tool", "ribbon");
  }

  function execute(
    id: CommandId,
    source: CommandContext["source"],
    args?: unknown,
  ) {
    executeCommand(id, { ...commandContext, source }, args as never);
  }

  function isCommandAvailable(id: CommandId) {
    return commandAvailable(id, { ...commandContext, source: "ribbon" });
  }

  function createDocument(typeId: string) {
    const documentType = documentTypes.find(({ id }) => id === typeId);

    if (!documentType) return;

    const id = `${documentType.id}-${nextDocumentId++}`;
    const title = `${documentType.label} ${documents.filter((document) => document.type === documentType.id).length + 1}`;

    documents = [...documents, { id, title, type: documentType.id }];
    activeDocumentId = id;
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
  <AppBar />
  <Ribbon>
    <Ribbon.Tab title="Home">
      <Ribbon.Section title="Tools">
        <Button
          aria-pressed={ui.currentTool === "select"}
          disabled={!isCommandAvailable("select-tool")}
          onclick={activateSelectTool}
          ><Icon name="cursor" size={22} /><span>Select</span></Button
        >
        <Button
          aria-pressed={ui.currentTool === "connect"}
          disabled={!isCommandAvailable("connect-tool")}
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
              disabled: !canEditTopology,
              onclick: () => armAssetPlacement("Server"),
            },
            {
              label: "Workstation",
              icon: "server",
              disabled: !canEditTopology,
              onclick: () => armAssetPlacement("Workstation"),
            },
            {
              label: "Firewall",
              icon: "shield",
              disabled: !canEditTopology,
              onclick: () => armAssetPlacement("Firewall"),
            },
            {
              label: "Database",
              icon: "server",
              disabled: !canEditTopology,
              onclick: () => armAssetPlacement("Database"),
            },
          ]}
          aria-label="Add server"
          aria-pressed={pendingAssetKind === "Server"}
          disabled={!canEditTopology}
          onclick={() => armAssetPlacement("Server")}
        >
          <Icon name="server" size={22} /><span>Asset</span>
        </SplitButton>
        <Button><Icon name="zone" size={22} /><span>Zone</span></Button>
      </Ribbon.Section>
      <Ribbon.Section title="Layout">
        <Select
          label="Topology layout"
          value={ui.topologyLayout}
          disabled={!isCommandAvailable("set-topology-layout")}
          onchange={(event) =>
            execute("set-topology-layout", "ribbon", {
              layout: event.currentTarget.value as TopologyLayout,
            })}
        >
          <option value="layered">Layered</option>
          <option value="force-directed">Force-directed</option>
          <option value="radial">Radial</option>
        </Select>
      </Ribbon.Section>
      <Ribbon.Section title="Display">
        <Checkbox
          checked={ui.showZoneBoundaries}
          disabled={!isCommandAvailable("toggle-zone-boundaries")}
          onchange={() => execute("toggle-zone-boundaries", "ribbon")}
          >Show zone boundaries</Checkbox
        >
      </Ribbon.Section>
      <Ribbon.Section title="Arrange">
        <Button
          variant="small"
          disabled={!isCommandAvailable("duplicate-selection")}
          onclick={() => execute("duplicate-selection", "ribbon")}
          ><Icon name="copy" size={16} /><span>Duplicate</span></Button
        >
        <Button
          variant="small"
          disabled={!isCommandAvailable("remove-selection")}
          onclick={() => execute("remove-selection", "ribbon")}
          ><Icon name="trash" size={16} /><span>Remove</span></Button
        >
        <Button
          variant="small"
          disabled={!isCommandAvailable("lock-selection")}
          onclick={() => execute("lock-selection", "ribbon")}
          ><Icon name="lock" size={16} /><span>Lock</span></Button
        >
        <Button
          variant="small"
          disabled={!isCommandAvailable("align-selection")}
          onclick={() => execute("align-selection", "ribbon")}
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
          disabled={!canEditTopology}
          onclick={() => armAssetPlacement("Server")}
          ><Icon name="server" size={22} /><span>Server</span></Button
        >
        <Button disabled
          ><Icon name="zone" size={22} /><span>Gateway</span></Button
        >
        <Button
          aria-pressed={ui.currentTool === "connect"}
          disabled={!isCommandAvailable("connect-tool")}
          onclick={activateConnectTool}
          ><Icon name="link" size={22} /><span>Trust link</span></Button
        >
      </Ribbon.Section>
    </Ribbon.Tab>
    <Ribbon.Tab title="Analyze">
      <Ribbon.Section title="Attack model">
        <Button
          disabled={!isCommandAvailable("run-simulation")}
          onclick={() => execute("run-simulation", "ribbon")}
          ><Icon name="play" size={22} /><span>Simulate</span></Button
        >
        <Button
          disabled={!isCommandAvailable("optimize-defense")}
          onclick={() => execute("optimize-defense", "ribbon")}
          ><Icon name="shield" size={22} /><span>Optimize</span></Button
        >
      </Ribbon.Section>
    </Ribbon.Tab>
    <Ribbon.Tab title="View">
      <Ribbon.Section title="Presentation">
        <RadioButton
          name="presentation"
          checked={ui.presentation === "graph"}
          disabled={!isCommandAvailable("show-graph")}
          onchange={() => execute("show-graph", "ribbon")}
          ><Icon name="graph" size={16} />Graph</RadioButton
        >
        <RadioButton
          name="presentation"
          checked={ui.presentation === "list"}
          disabled={!isCommandAvailable("show-list")}
          onchange={() => execute("show-list", "ribbon")}
          ><Icon name="list" size={16} />List</RadioButton
        >
        <Button
          aria-pressed={ui.inspectorVisible}
          onclick={() => execute("toggle-inspector", "ribbon")}
          ><Icon name="chevron-right" size={22} /><span>Inspector</span></Button
        >
      </Ribbon.Section>
    </Ribbon.Tab>
  </Ribbon>
  {#snippet inspector()}
    {#if ui.inspectorVisible}
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
            tool={ui.currentTool}
            placementKind={pendingAssetKind}
            onPlacementConsumed={() => (pendingAssetKind = undefined)}
            onSelectionChange={setSelectedObject}
            onEdgeCreated={() => updateUi({ currentTool: "select" })}
          />
        {/if}
      </Workspace.Document>
    {/each}
  </Workspace>
  <StatusBar
    documentName={activeDocument?.title ?? "No document"}
    statusMessage={serverStatus}
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
</style>
