<script lang="ts">
  import Button from "./controls/Button.svelte";
  import Icon from "./controls/Icon.svelte";
  import Ribbon from "./ribbon/Ribbon";
  import Slider from "./controls/Slider.svelte";
  import type { ForceParams } from "./layout/ForceLayout.types";

  interface Props {
    hasActiveCanvas: boolean;
    hasUnreadReport: boolean;
    forceParams: ForceParams;
    onForceParamsChange: (change: Partial<ForceParams>) => void;
    onForceLayout: () => void;
    onRunSimulation: () => void;
    onShowReport: () => void;
  }

  let {
    hasActiveCanvas,
    hasUnreadReport,
    forceParams,
    onForceParamsChange,
    onForceLayout,
    onRunSimulation,
    onShowReport,
  }: Props = $props();
</script>

<Ribbon
  tabDecorations={{
    Report: {
      color: "var(--ds-color-warning)",
      animate: hasUnreadReport ? "pulse" : undefined,
    },
  }}
>
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
        label="Repulsion"
        min={-1000}
        max={-10}
        value={forceParams.repulsion}
        onchange={(v) => onForceParamsChange({ repulsion: v })}
        disabled={!hasActiveCanvas}
      />
      <Slider
        label="Link dist."
        min={50}
        max={500}
        value={forceParams.linkDistance}
        onchange={(v) => onForceParamsChange({ linkDistance: v })}
        disabled={!hasActiveCanvas}
      />
      <Slider
        label="Collision rad."
        min={30}
        max={150}
        value={forceParams.collisionRadius}
        onchange={(v) => onForceParamsChange({ collisionRadius: v })}
        disabled={!hasActiveCanvas}
      />
      <Slider
        label="Center grav."
        min={0}
        max={0.3}
        step={0.01}
        value={forceParams.centerStrength}
        onchange={(v) => onForceParamsChange({ centerStrength: v })}
        disabled={!hasActiveCanvas}
      />
      <Slider
        label="Alpha decay"
        min={0.005}
        max={0.1}
        step={0.005}
        value={forceParams.alphaDecay}
        onchange={(v) => onForceParamsChange({ alphaDecay: v })}
        disabled={!hasActiveCanvas}
      />
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="Analyze">
    <Ribbon.Section title="Attack model">
      <Button onclick={(_) => onRunSimulation()}
        ><Icon name="play" size={22} /><span>Simulate</span></Button
      >
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
  <Ribbon.Tab title="Analyze">
    <Ribbon.Section title="Attack model">
      <Button onclick={(_) => onRunSimulation()}
        ><Icon name="play" size={22} /><span>Simulate</span></Button
      >
      <Button><Icon name="shield" size={22} /><span>Optimize</span></Button>
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="Report">
    <Ribbon.Section title="Reports">
      <Button onclick={(_) => onShowReport()}
        ><Icon name="shield" size={22} /><span>Show report</span></Button
      >
    </Ribbon.Section>
  </Ribbon.Tab>
</Ribbon>
