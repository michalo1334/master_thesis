<script lang="ts">
  import { Tabs } from "bits-ui";
  import Icon from "./Icon.svelte";
  import type { IconName, ViewMode } from "./types";

  interface Props {
    activeView: ViewMode;
    onViewChange: (view: ViewMode) => void;
    onToggleInspector: () => void;
  }

  interface Command {
    id: string;
    label: string;
    icon: IconName;
    action?: () => void;
    pressed?: boolean;
    compact?: boolean;
  }

  let { activeView, onViewChange, onToggleInspector }: Props = $props();
  let activeTab = $state("home");

  let homeCommands = $derived<Command[]>([
    { id: "select", label: "Select", icon: "cursor", pressed: true },
    { id: "connect", label: "Connect", icon: "link" },
    { id: "asset", label: "Asset", icon: "server" },
    { id: "zone", label: "Zone", icon: "zone" }
  ]);
</script>

<nav class="dashboard-ribbon" aria-label="Editor ribbon">
  <Tabs.Root bind:value={activeTab} loop activationMode="automatic">
    <Tabs.List class="dashboard-ribbon-tabs" aria-label="Ribbon tabs">
      <Tabs.Trigger class="dashboard-ribbon-tab" value="home">Home</Tabs.Trigger>
      <Tabs.Trigger class="dashboard-ribbon-tab" value="insert">Insert</Tabs.Trigger>
      <Tabs.Trigger class="dashboard-ribbon-tab" value="analyze">Analyze</Tabs.Trigger>
      <Tabs.Trigger class="dashboard-ribbon-tab" value="view">View</Tabs.Trigger>
    </Tabs.List>

    <Tabs.Content class="dashboard-ribbon-panel" value="home">
      <div class="dashboard-ribbon-group">
        {#each homeCommands.slice(0, 2) as command (command.id)}
          <button class="dashboard-ribbon-command" aria-pressed={command.pressed || undefined} onclick={command.action}>
            <Icon name={command.icon} size={22} /><span>{command.label}</span>
          </button>
        {/each}
        <span class="dashboard-ribbon-group-label">Tools</span>
      </div>
      <div class="dashboard-ribbon-group">
        {#each homeCommands.slice(2) as command (command.id)}
          <button class="dashboard-ribbon-command"><Icon name={command.icon} size={22} /><span>{command.label}</span></button>
        {/each}
        <span class="dashboard-ribbon-group-label">Add</span>
      </div>
      <div class="dashboard-ribbon-group dashboard-ribbon-group-stacked">
        <button class="dashboard-ribbon-command compact"><Icon name="copy" size={16} /><span>Duplicate</span></button>
        <button class="dashboard-ribbon-command compact"><Icon name="trash" size={16} /><span>Remove</span></button>
        <button class="dashboard-ribbon-command compact"><Icon name="lock" size={16} /><span>Lock</span></button>
        <button class="dashboard-ribbon-command compact"><Icon name="align" size={16} /><span>Align</span></button>
        <span class="dashboard-ribbon-group-label">Arrange</span>
      </div>
      <div class="dashboard-ribbon-group dashboard-ribbon-optional">
        <button class="dashboard-ribbon-command"><Icon name="shield" size={22} /><span>Defense</span></button>
        <button class="dashboard-ribbon-command"><Icon name="tag" size={22} /><span>Classify</span></button>
        <span class="dashboard-ribbon-group-label">Security</span>
      </div>
    </Tabs.Content>

    <Tabs.Content class="dashboard-ribbon-panel" value="insert">
      <div class="dashboard-ribbon-group">
        <button class="dashboard-ribbon-command"><Icon name="server" size={22} /><span>Server</span></button>
        <button class="dashboard-ribbon-command"><Icon name="zone" size={22} /><span>Gateway</span></button>
        <button class="dashboard-ribbon-command"><Icon name="link" size={22} /><span>Trust link</span></button>
        <span class="dashboard-ribbon-group-label">Topology</span>
      </div>
    </Tabs.Content>

    <Tabs.Content class="dashboard-ribbon-panel" value="analyze">
      <div class="dashboard-ribbon-group">
        <button class="dashboard-ribbon-command"><Icon name="play" size={22} /><span>Simulate</span></button>
        <button class="dashboard-ribbon-command"><Icon name="shield" size={22} /><span>Optimize</span></button>
        <span class="dashboard-ribbon-group-label">Attack model</span>
      </div>
    </Tabs.Content>

    <Tabs.Content class="dashboard-ribbon-panel" value="view">
      <div class="dashboard-ribbon-group">
        <button class="dashboard-ribbon-command" aria-pressed={activeView === "graph"} onclick={() => onViewChange("graph")}><Icon name="graph" size={22} /><span>Graph</span></button>
        <button class="dashboard-ribbon-command" aria-pressed={activeView === "list"} onclick={() => onViewChange("list")}><Icon name="list" size={22} /><span>List</span></button>
        <button class="dashboard-ribbon-command" onclick={onToggleInspector}><Icon name="chevron-right" size={22} /><span>Inspector</span></button>
        <span class="dashboard-ribbon-group-label">Presentation</span>
      </div>
    </Tabs.Content>
  </Tabs.Root>
</nav>

<style>
  .dashboard-ribbon { grid-area: ribbon; min-width: 0; background: var(--ds-color-paper); border-bottom: 1px solid var(--ds-color-border); box-shadow: var(--ds-shadow-sm); z-index: 3; }
  /* Bits UI renders the tab elements; keep its boundary crossing anchored to this ribbon. */
  .dashboard-ribbon > :global([data-tabs-root]) { min-height: 100%; display: grid; grid-template-rows: minmax(var(--ds-ribbon-tabs-height), auto) minmax(0, 1fr); }
  .dashboard-ribbon :global(.dashboard-ribbon-tabs) { display: flex; align-items: end; gap: 0.125rem; padding: 0 var(--ds-space-3); border-bottom: 1px solid var(--ds-color-border-soft); }
  .dashboard-ribbon :global(.dashboard-ribbon-tab) { min-height: var(--ds-document-tab-height); padding: 0 0.9375rem; border: 0; border-bottom: 2px solid transparent; background: transparent; color: var(--ds-color-text-secondary); }
  .dashboard-ribbon :global(.dashboard-ribbon-tab[data-state="active"]) { color: var(--ds-color-accent); border-bottom-color: var(--ds-color-accent); font-weight: 600; }
  .dashboard-ribbon :global(.dashboard-ribbon-panel) { display: flex; min-width: 0; padding: 0.4375rem 0.625rem 0.3125rem; overflow: hidden; }
  .dashboard-ribbon-group { position: relative; display: flex; align-items: stretch; gap: 0.1875rem; padding: 0 0.625rem var(--ds-space-4); border-right: 1px solid var(--ds-color-border-soft); }
  .dashboard-ribbon-group:first-child { padding-left: 0.1875rem; }
  .dashboard-ribbon-group-label { position: absolute; inset: auto 0 0; text-align: center; color: var(--ds-color-text-faint); font-size: var(--ds-text-xs); }
  .dashboard-ribbon-command { min-width: 3.125rem; min-height: 3.875rem; padding: 0.3125rem 0.4375rem; border: 1px solid transparent; border-radius: var(--ds-radius-md); background: transparent; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: var(--ds-space-1); --dashboard-icon-color: #315f9a; }
  .dashboard-ribbon-command:hover, .dashboard-ribbon-command[aria-pressed="true"] { background: var(--ds-color-accent-soft); border-color: #b9d5f8; }
  .dashboard-ribbon-group-stacked { display: grid; grid-template-columns: repeat(2, minmax(4.625rem, 1fr)); align-content: start; }
  .dashboard-ribbon-command.compact { min-width: 4.625rem; min-height: var(--ds-control-height); flex-direction: row; justify-content: flex-start; }

  @media (max-width: 65.625em) {
    .dashboard-ribbon :global(.dashboard-ribbon-panel) { padding-block: 0.1875rem; }
    .dashboard-ribbon-group { padding-inline: 0.3125rem; }
    .dashboard-ribbon-command { min-height: 2.4375rem; min-width: 2.6875rem; }
    .dashboard-ribbon-command > span { display: none; }
    .dashboard-ribbon-group-stacked { display: flex; }
    .dashboard-ribbon-optional { display: none; }
  }

  @media (max-width: 47.5em) {
    .dashboard-ribbon :global(.dashboard-ribbon-tabs) { padding-left: 0.3125rem; }
    .dashboard-ribbon :global(.dashboard-ribbon-tab) { padding-inline: 0.5625rem; }
    .dashboard-ribbon :global(.dashboard-ribbon-panel) { padding: 0.1875rem 0.3125rem; }
    .dashboard-ribbon-group { padding: 0 0.1875rem; border: 0; }
    .dashboard-ribbon-group-label, .dashboard-ribbon-command > span { display: none; }
    .dashboard-ribbon-command, .dashboard-ribbon-command.compact { min-width: 2rem; width: 2rem; min-height: 2rem; padding: var(--ds-space-1); justify-content: center; }
  }

  @media (forced-colors: active) {
    .dashboard-ribbon :global(.dashboard-ribbon-tab[data-state="active"]) { outline: 2px solid Highlight; }
  }
</style>
