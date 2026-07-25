<script lang="ts">
  import Button from "../ui/Button.svelte";
  import Icon from "../ui/Icon.svelte";
  import Ribbon from "../ribbon/Ribbon";
  import Slider from "../ui/Slider.svelte";
  import SplitButton, {
    type SplitButtonOption,
  } from "../ui/SplitButton.svelte";
  import type { ForceParams } from "../graph/layout/ForceLayout.types";
  import type { SimulationParams } from "../contract";
  import Checkbox from "../ui/Checkbox.svelte";
  import NumberInput from "../ui/NumberInput.svelte";
  import Select from "../ui/Select.svelte";

  interface Props {
    hasActiveGraph: boolean;
    hasUnreadReport: boolean;
    isLoadingExperiments: boolean;
    forceParams: ForceParams;
    onForceParamsChange: (change: Partial<ForceParams>) => void;
    onForceLayout: () => void;
    onRunSimulation: () => void;
    onShowExperiments: () => void;
    onOptimize: (strategyId: string) => void;
    optimizationOptions: readonly SplitButtonOption[];
    activeOptimizationId: string;
    onSimulationParamsChange: (change: Partial<SimulationParams>) => void;
    simulationParams: SimulationParams;
    footholdHosts: readonly { id: string; name: string }[];
  }

  let {
    hasActiveGraph,
    hasUnreadReport,
    isLoadingExperiments,
    forceParams,
    onForceParamsChange,
    onForceLayout,
    onRunSimulation,
    onShowExperiments,
    onOptimize,
    optimizationOptions,
    activeOptimizationId,
    onSimulationParamsChange,
    simulationParams,
    footholdHosts,
  }: Props = $props();

  let doRandomSeed = $state(false);
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
      <Button disabled={!hasActiveGraph} onclick={onForceLayout}
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
        disabled={!hasActiveGraph}
      />
      <Slider
        label="Link dist."
        min={50}
        max={500}
        value={forceParams.linkDistance}
        onchange={(v) => onForceParamsChange({ linkDistance: v })}
        disabled={!hasActiveGraph}
      />
      <Slider
        label="Collision rad."
        min={30}
        max={150}
        value={forceParams.collisionRadius}
        onchange={(v) => onForceParamsChange({ collisionRadius: v })}
        disabled={!hasActiveGraph}
      />
      <Slider
        label="Center grav."
        min={0}
        max={0.3}
        step={0.01}
        value={forceParams.centerStrength}
        onchange={(v) => onForceParamsChange({ centerStrength: v })}
        disabled={!hasActiveGraph}
      />
      <Slider
        label="Alpha decay"
        min={0.005}
        max={0.1}
        step={0.005}
        value={forceParams.alphaDecay}
        onchange={(v) => onForceParamsChange({ alphaDecay: v })}
        disabled={!hasActiveGraph}
      />
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="Analyze">
    <Ribbon.Section title="Attack model">
      <Button
        onclick={onRunSimulation}
        disabled={!hasActiveGraph || footholdHosts.length === 0}
        ><Icon name="play" size={22} /><span>Simulate</span></Button
      >
      <SplitButton
        options={optimizationOptions}
        activeId={activeOptimizationId}
        disabled={!hasActiveGraph}
        ariaLabel="Optimize"
        onSelect={onOptimize}
      />
    </Ribbon.Section>
    <Ribbon.Section title="Simulation parameters">
      <Select
        label="Initial foothold"
        value={simulationParams.initial_foothold_node_id}
        disabled={!hasActiveGraph || footholdHosts.length === 0}
        onchange={(event) =>
          onSimulationParamsChange({
            initial_foothold_node_id: event.currentTarget.value,
          })}
      >
        {#each footholdHosts as host (host.id)}
          <option value={host.id}>{host.name}</option>
        {/each}
      </Select>
      <Slider
        label="Monte Carlo trials"
        min={1}
        max={40000}
        step={1000}
        value={simulationParams.monte_carlo_trials}
        onchange={(v) => onSimulationParamsChange({ monte_carlo_trials: v })}
        disabled={!hasActiveGraph}
      />
      <Slider
        label="Iterations per simulation"
        min={1}
        max={40000}
        step={1000}
        value={simulationParams.iterations_per_run}
        onchange={(v) => onSimulationParamsChange({ iterations_per_run: v })}
        disabled={!hasActiveGraph}
      />
      <div class="dashboard-seed-group">
        <NumberInput
          label="Seed"
          disabled={doRandomSeed}
          onchange={(v) => onSimulationParamsChange({ seed: v })}
        />
        <Checkbox
          label="Random"
          bind:checked={doRandomSeed}
          onchange={(v) => onSimulationParamsChange({ generate_seed: v })}
        />
      </div>
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="View">
    <Ribbon.Section title="Workspace">
      <Button
        ><Icon name="chevron-right" size={22} /><span>Inspector</span></Button
      >
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="Report">
    <Ribbon.Section title="Reports">
      <Button
        disabled={isLoadingExperiments}
        onclick={(_) => onShowExperiments()}
        ><Icon name="shield" size={22} /><span>Show experiments</span></Button
      >
    </Ribbon.Section>
  </Ribbon.Tab>
</Ribbon>

<style>
  .dashboard-seed-group {
    display: flex;
    flex-direction: column;
    gap: 0.125rem;
  }
</style>
