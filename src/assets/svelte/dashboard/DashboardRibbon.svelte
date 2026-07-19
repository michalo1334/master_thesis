<script lang="ts">
  import Button from "./controls/Button.svelte";
  import Icon from "./controls/Icon.svelte";
  import Ribbon from "./ribbon/Ribbon";
  import Slider from "./controls/Slider.svelte";
  import type { LayoutGraphParams } from "./contract";

  interface Props {
    hasActiveCanvas: boolean;
    layoutParams: LayoutGraphParams;
    onLayoutParamsChange: (change: Partial<LayoutGraphParams>) => void;
    onForceLayout: () => void;
  }

  let {
    hasActiveCanvas,
    layoutParams,
    onLayoutParamsChange,
    onForceLayout,
  }: Props = $props();
</script>

<Ribbon>
  <Ribbon.Tab title="Home">
    <Ribbon.Section title="Tools">
      <Button><Icon name="cursor" size={22} /><span>Select</span></Button>
      <Button><Icon name="link" size={22} /><span>Connect</span></Button>
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="Layout">
    <Ribbon.Section title="Layout">
      <Button disabled={!hasActiveCanvas} onclick={onForceLayout}
        ><Icon name="squares-2x2" size={22} /><span>Force-directed</span
        ></Button
      >
    </Ribbon.Section>
    <Ribbon.Section title="Parameters">
      <Slider
        label="Iterations"
        min={1}
        max={500}
        value={layoutParams.iterations}
        onchange={(v) => onLayoutParamsChange({ iterations: v })}
        disabled={!hasActiveCanvas}
      />
      <Slider
        label="Spring"
        min={50}
        max={500}
        value={layoutParams.springLength}
        onchange={(v) => onLayoutParamsChange({ springLength: v })}
        disabled={!hasActiveCanvas}
      />
      <Slider
        label="Repulsion"
        min={1}
        max={100}
        value={layoutParams.repulsion}
        onchange={(v) => onLayoutParamsChange({ repulsion: v })}
        disabled={!hasActiveCanvas}
      />
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
