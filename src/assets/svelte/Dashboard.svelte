<script lang="ts">
  import AppBar from "./dashboard/AppBar.svelte";
  import Button from "./dashboard/Button.svelte";
  import Checkbox from "./dashboard/Checkbox.svelte";
  import Icon from "./dashboard/Icon.svelte";
  import RadioButton from "./dashboard/RadioButton.svelte";
  import Ribbon from "./dashboard/Ribbon";
  import Select from "./dashboard/Select.svelte";
  import SplitButton from "./dashboard/SplitButton.svelte";
</script>

<div class="dashboard-app" data-dashboard-theme="topology">
  <AppBar/>
  <Ribbon>
    <Ribbon.Tab title="Home">
      <Ribbon.Section title="Tools">
        <Button><Icon name="cursor" size={22} /><span>Select</span></Button>
        <Button><Icon name="link" size={22} /><span>Connect</span></Button>
      </Ribbon.Section>
      <Ribbon.Section title="Add">
        <SplitButton items={[
          { label: "Server", icon: "server" },
          { label: "Workstation", icon: "server" },
          { label: "Firewall", icon: "shield" },
          { label: "Database", icon: "server" }
        ]}>
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
        <Button variant="small"><Icon name="copy" size={16} /><span>Duplicate</span></Button>
        <Button variant="small"><Icon name="trash" size={16} /><span>Remove</span></Button>
        <Button variant="small"><Icon name="lock" size={16} /><span>Lock</span></Button>
        <Button variant="small"><Icon name="align" size={16} /><span>Align</span></Button>
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
        <RadioButton name="presentation" checked><Icon name="graph" size={16} />Graph</RadioButton>
        <RadioButton name="presentation"><Icon name="list" size={16} />List</RadioButton>
        <Button><Icon name="chevron-right" size={22} /><span>Inspector</span></Button>
      </Ribbon.Section>
    </Ribbon.Tab>
  </Ribbon>
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

</style>
