<script lang="ts">
  import RibbonButton from "../ui/RibbonButton.svelte";
  import Icon from "../ui/Icon.svelte";
  import Ribbon from "../ribbon/Ribbon";
  import Slider from "../ui/Slider.svelte";
  import SplitButton, {
    type SplitButtonOption,
  } from "../ui/SplitButton.svelte";
  import type { ForceParams } from "../graph/layout/ForceLayout.types";
  import type { OptimizationParams, SimulationParams } from "../contract";
  import type { OptimizationParamsChange } from "../workspace/WorkspaceModel.svelte";
  import Checkbox from "../ui/Checkbox.svelte";
  import NumberInput from "../ui/NumberInput.svelte";
  import Select from "../ui/Select.svelte";

  type OptimizationOption = SplitButtonOption & {
    id: OptimizationParams["strategy"];
  };

  interface Props {
    hasActiveGraph: boolean;
    hasUnreadReport: boolean;
    isLoadingExperiments: boolean;
    forceParams: ForceParams;
    onForceParamsChange: (change: Partial<ForceParams>) => void;
    onForceLayout: () => void;
    onRunSimulation: () => void;
    onShowExperiments: () => void;
    onOptimize: (strategyId: OptimizationParams["strategy"]) => void;
    optimizationOptions: readonly OptimizationOption[];
    activeOptimizationId: OptimizationParams["strategy"];
    optimizationParams: OptimizationParams & {
      simulation_params: SimulationParams;
    };
    onOptimizationParamsChange: (change: OptimizationParamsChange) => void;
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
    optimizationParams,
    onOptimizationParamsChange,
    onSimulationParamsChange,
    simulationParams,
    footholdHosts,
  }: Props = $props();

  let availableOptimizationOptions = $derived(
    footholdHosts.length === 0
      ? optimizationOptions.map((option) =>
          option.id === "cvss" ? option : { ...option, disabled: true },
        )
      : optimizationOptions,
  );

  function handleOptimizationSelect(id: string): void {
    const option = availableOptimizationOptions.find(
      (option) => option.id === id,
    );
    if (option && !option.disabled) onOptimize(option.id);
  }
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
      <RibbonButton
        ><Icon name="cursor" size={22} /><span>Select</span></RibbonButton
      >
      <RibbonButton
        ><Icon name="link" size={22} /><span>Connect</span></RibbonButton
      >
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="Layout">
    <Ribbon.Section title="Layout">
      <RibbonButton disabled={!hasActiveGraph} onclick={onForceLayout}
        ><Icon name="squares-2x2" size={22} /><span>Force-directed</span
        ></RibbonButton
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
      <RibbonButton
        onclick={onRunSimulation}
        disabled={!hasActiveGraph || footholdHosts.length === 0}
        ><Icon name="play" size={22} /><span>Simulate</span></RibbonButton
      >
      <SplitButton
        options={availableOptimizationOptions}
        activeId={activeOptimizationId}
        disabled={!hasActiveGraph}
        ariaLabel="Optimize"
        onSelect={handleOptimizationSelect}
      />
    </Ribbon.Section>
    <Ribbon.Section title="Optimization parameters">
      <NumberInput
        label="Budget"
        value={optimizationParams.budget}
        min={1}
        disabled={!hasActiveGraph}
        onchange={(budget) => onOptimizationParamsChange({ budget })}
      />
    </Ribbon.Section>
    {#if activeOptimizationId !== "cvss"}
      <Ribbon.Section title="Optimization simulation">
        <Select
          label="Initial foothold"
          value={optimizationParams.simulation_params.initial_foothold_node_id}
          disabled={!hasActiveGraph || footholdHosts.length === 0}
          onchange={(event) =>
            onOptimizationParamsChange({
              simulation_params: {
                initial_foothold_node_id: event.currentTarget.value,
              },
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
          value={optimizationParams.simulation_params.monte_carlo_trials}
          onchange={(monte_carlo_trials) =>
            onOptimizationParamsChange({
              simulation_params: { monte_carlo_trials },
            })}
          disabled={!hasActiveGraph}
        />
        <Slider
          label="Iterations per simulation"
          min={1}
          max={40000}
          step={1000}
          value={optimizationParams.simulation_params.iterations_per_run}
          onchange={(iterations_per_run) =>
            onOptimizationParamsChange({
              simulation_params: { iterations_per_run },
            })}
          disabled={!hasActiveGraph}
        />
        <NumberInput
          label="Maximum attempts"
          value={optimizationParams.simulation_params.max_attempts}
          min={1}
          disabled={!hasActiveGraph}
          onchange={(max_attempts) =>
            onOptimizationParamsChange({
              simulation_params: { max_attempts },
            })}
        />
        <div class="dashboard-seed-group">
          <NumberInput
            label="Seed"
            value={optimizationParams.simulation_params.seed}
            disabled={optimizationParams.simulation_params.generate_seed}
            onchange={(seed) =>
              onOptimizationParamsChange({ simulation_params: { seed } })}
          />
          <Checkbox
            label="Random"
            checked={optimizationParams.simulation_params.generate_seed}
            onchange={(generate_seed) =>
              onOptimizationParamsChange({
                simulation_params: { generate_seed },
              })}
          />
        </div>
      </Ribbon.Section>
    {/if}
    <Ribbon.Section title="Standalone simulation">
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
          value={simulationParams.seed}
          disabled={simulationParams.generate_seed}
          onchange={(v) => onSimulationParamsChange({ seed: v })}
        />
        <Checkbox
          label="Random"
          checked={simulationParams.generate_seed}
          onchange={(v) => onSimulationParamsChange({ generate_seed: v })}
        />
      </div>
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="View">
    <Ribbon.Section title="Workspace">
      <RibbonButton
        ><Icon name="chevron-right" size={22} /><span>Inspector</span
        ></RibbonButton
      >
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="Report">
    <Ribbon.Section title="Reports">
      <RibbonButton
        disabled={isLoadingExperiments}
        onclick={(_) => onShowExperiments()}
        ><Icon name="shield" size={22} /><span>Show experiments</span
        ></RibbonButton
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
