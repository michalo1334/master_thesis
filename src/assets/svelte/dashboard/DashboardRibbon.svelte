<script lang="ts">
  import Button from "./controls/Button.svelte";
  import Icon from "./controls/Icon.svelte";
  import Ribbon from "./ribbon/Ribbon";

  interface Props {}

  let {}: Props = $props();
</script>

<Ribbon>
  <Ribbon.Tab title="Home">
    <Ribbon.Section title="Tools">
      <Button><Icon name="cursor" size={22} /><span>Select</span></Button>
      <Button><Icon name="link" size={22} /><span>Connect</span></Button>
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="Analyze">
    <Ribbon.Section title="Attack model">
      <Button><Icon name="play" size={22} /><span>Simulate</span></Button>
      <Button><Icon name="shield" size={22} /><span>Optimize</span></Button>
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="View">
    <Ribbon.Section title="Workspace">
      <Button
        ><Icon name="chevron-right" size={22} /><span>Inspector</span></Button
      >
    </Ribbon.Section>
  </Ribbon.Tab>
</Ribbon>
