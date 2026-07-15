<script lang="ts">
  import AppBar from "./dashboard/shell/AppBar.svelte";
  import Button from "./dashboard/controls/Button.svelte";
  import Checkbox from "./dashboard/controls/Checkbox.svelte";
  import Icon from "./dashboard/controls/Icon.svelte";
  import RadioButton from "./dashboard/controls/RadioButton.svelte";
  import Ribbon from "./dashboard/ribbon/Ribbon";
  import Select from "./dashboard/controls/Select.svelte";
  import SplitButton from "./dashboard/controls/SplitButton.svelte";
  import SimulationReport from "./dashboard/statistics/SimulationReport.svelte";
  import Workspace from "./dashboard/workspace/Workspace";

  type DocumentType = "topology" | "simulation";

  interface WorkspaceDocument {
    id: string;
    title: string;
    type: DocumentType;
  }

  const documentTypes = [
    { id: "topology", label: "Topology", icon: "graph" },
    { id: "simulation", label: "Simulation result", icon: "play" },
  ] as const;

  let documents = $state<WorkspaceDocument[]>([]);
  let activeDocumentId = $state<string>();
  let nextDocumentId = 1;

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
        <Button><Icon name="cursor" size={22} /><span>Select</span></Button>
        <Button><Icon name="link" size={22} /><span>Connect</span></Button>
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
        <Select label="Topology layout" value="Layered">
          <option>Layered</option>
          <option>Force-directed</option>
          <option>Radial</option>
        </Select>
      </Ribbon.Section>
      <Ribbon.Section title="Display">
        <Checkbox checked>Show zone boundaries</Checkbox>
      </Ribbon.Section>
      <Ribbon.Section title="Arrange">
        <Button variant="small"
          ><Icon name="copy" size={16} /><span>Duplicate</span></Button
        >
        <Button variant="small"
          ><Icon name="trash" size={16} /><span>Remove</span></Button
        >
        <Button variant="small"
          ><Icon name="lock" size={16} /><span>Lock</span></Button
        >
        <Button variant="small"
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
        <Button><Icon name="play" size={22} /><span>Simulate</span></Button>
        <Button><Icon name="shield" size={22} /><span>Optimize</span></Button>
      </Ribbon.Section>
    </Ribbon.Tab>
    <Ribbon.Tab title="View">
      <Ribbon.Section title="Presentation">
        <RadioButton name="presentation" checked
          ><Icon name="graph" size={16} />Graph</RadioButton
        >
        <RadioButton name="presentation"
          ><Icon name="list" size={16} />List</RadioButton
        >
        <Button
          ><Icon name="chevron-right" size={22} /><span>Inspector</span></Button
        >
      </Ribbon.Section>
    </Ribbon.Tab>
  </Ribbon>
  <Workspace
    {activeDocumentId}
    onActiveDocumentChange={(id) => (activeDocumentId = id)}
    onCloseDocument={closeDocument}
    {documentTypes}
    onCreateDocument={createDocument}
  >
    {#each documents as document (document.id)}
      <Workspace.Document id={document.id} title={document.title}>
        {#if document.type === "simulation"}
          <SimulationReport title={document.title} />
        {:else}
          <section class="dashboard-document-placeholder">
            <h1>{document.title}</h1>
            <p>Topology canvas coming soon.</p>
          </section>
        {/if}
      </Workspace.Document>
    {/each}
  </Workspace>
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

  .dashboard-document-placeholder {
    height: 100%;
    padding: 2rem;
    color: var(--ds-color-text-secondary);
    background: var(--ds-color-surface);
  }

  .dashboard-document-placeholder h1,
  .dashboard-document-placeholder p {
    margin: 0;
  }

  .dashboard-document-placeholder p {
    margin-top: var(--ds-space-2);
  }
</style>
