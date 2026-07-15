<script lang="ts">
  import type { Live } from "live_svelte";
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
  import TopologyContextMenu from "./dashboard/commands/TopologyContextMenu.svelte";
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

  type DocumentType = "topology" | "simulation";

  interface WorkspaceDocument {
    id: string;
    title: string;
    type: DocumentType;
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

  let documents = $state<WorkspaceDocument[]>([]);
  let activeDocumentId = $state<string>();
  let nextDocumentId = 1;
  let activeDocument = $derived(
    documents.find((document) => document.id === activeDocumentId),
  );
  let selectedObject = $state<SelectedTopologyObject>();
  let serverStatus = $derived(serverCommand?.message);
  let ui = $state<DashboardUiState>({
    currentTool: "select",
    topologyLayout: "layered",
    showZoneBoundaries: true,
    inspectorVisible: true,
    presentation: "graph",
  });
  const reconciledServerCommandVersions = new SvelteSet<number>();
  const topologyPlaceholderObject: SelectedTopologyObject = {
    id: "topology-surface",
    name: "Topology surface",
  };

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

  $effect(() => {
    if (serverCommand) reconcileServerCommand(serverCommand);
  });

  function reconcileServerCommand(command: ServerCommand) {
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
          onclick={() => execute("select-tool", "ribbon")}
          ><Icon name="cursor" size={22} /><span>Select</span></Button
        >
        <Button
          aria-pressed={ui.currentTool === "connect"}
          disabled={!isCommandAvailable("connect-tool")}
          onclick={() => execute("connect-tool", "ribbon")}
          ><Icon name="link" size={22} /><span>Connect</span></Button
        >
      </Ribbon.Section>
      <Ribbon.Section title="Add">
        <SplitButton
          items={[
            { label: "Server", icon: "server" },
            { label: "Workstation", icon: "server" },
            { label: "Firewall", icon: "shield" },
            { label: "Database", icon: "server" },
          ]}
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
        <Button><Icon name="server" size={22} /><span>Server</span></Button>
        <Button><Icon name="zone" size={22} /><span>Gateway</span></Button>
        <Button><Icon name="link" size={22} /><span>Trust link</span></Button>
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
            : "Select an object in the active document to inspect its properties."}
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
          <TopologyContextMenu
            context={commandContext}
            topologyObject={topologyPlaceholderObject}
          >
            <h1>{document.title}</h1>
            <p>
              {ui.showZoneBoundaries
                ? "Zone boundaries shown."
                : "Zone boundaries hidden."} Right-click for topology commands.
            </p>
          </TopologyContextMenu>
        {/if}
      </Workspace.Document>
    {/each}
  </Workspace>
  <StatusBar
    selectedName={selectedObject?.name ??
      activeDocument?.title ??
      "No document"}
    zoom={100}
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
