<script lang="ts">
  import RibbonButton from "../../ui-kit/primitives/RibbonButton.svelte";
  import Icon from "../../ui-kit/primitives/Icon.svelte";
  import { Ribbon } from "../../ui-kit/layout";
  import Slider from "../../ui-kit/primitives/Slider.svelte";
  import type { ForceParams } from "../graph/layout/ForceLayout.types";
  import type {
    OptimizationParams,
    OptimizationParamsChange,
    SimulationParams,
  } from "../contract";
  import Checkbox from "../../ui-kit/primitives/Checkbox.svelte";
  import NumberInput from "../../ui-kit/primitives/NumberInput.svelte";
  import Select from "../../ui-kit/primitives/Select.svelte";

  type OptimizationOption = {
    id: OptimizationParams["strategy"];
    title: string;
    disabled?: boolean;
  };

  interface Props {
    hasActiveGraph: boolean;
    forceParams: ForceParams;
    onForceParamsChange: (change: Partial<ForceParams>) => void;
    onForceLayout: () => void;
    onArrangeNetwork?: () => void;
    onRunSimulation: () => void;
    onCompareGraphs: () => void;
    onOpenAnalysis: () => void;
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
    analysisRunning?: boolean;
  }

  let {
    hasActiveGraph,
    forceParams,
    onForceParamsChange,
    onForceLayout,
    onArrangeNetwork = () => {},
    onRunSimulation,
    onCompareGraphs,
    onOpenAnalysis,
    onOptimize,
    optimizationOptions,
    activeOptimizationId,
    optimizationParams,
    onOptimizationParamsChange,
    onSimulationParamsChange,
    simulationParams,
    footholdHosts,
    analysisRunning = false,
  }: Props = $props();

  let availableOptimizationOptions = $derived(
    footholdHosts.length === 0
      ? optimizationOptions.map((option) =>
          option.id === "cvss" ? option : { ...option, disabled: true },
        )
      : optimizationOptions,
  );
</script>

<Ribbon>
  <Ribbon.Tab title="Home">
    <Ribbon.Section title="Tools">
      <RibbonButton onclick={onCompareGraphs} aria-label="Compare graphs"
        ><Icon name="graph" size={22} /><span>Compare graphs</span
        ></RibbonButton
      >
      <RibbonButton onclick={onOpenAnalysis} aria-label="Analysis"
        ><Icon name="graph" size={22} /><span>Analysis</span></RibbonButton
      >
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="Layout">
    <Ribbon.Section title="Layout">
      <RibbonButton disabled={!hasActiveGraph} onclick={onForceLayout}
        ><Icon name="squares-2x2" size={22} /><span>Force-directed</span
        ></RibbonButton
      >
      <RibbonButton disabled={!hasActiveGraph} onclick={onArrangeNetwork}
        ><Icon name="graph" size={22} /><span>Arrange network</span
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
  <Ribbon.Tab title="Simulation">
    <Ribbon.Section title="Attack model">
      <RibbonButton
        onclick={onRunSimulation}
        disabled={!hasActiveGraph ||
          footholdHosts.length === 0 ||
          analysisRunning}
        ><Icon name="play" size={22} /><span>Simulate</span></RibbonButton
      >
    </Ribbon.Section>
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
  <Ribbon.Tab title="Optimization">
    <Ribbon.Section title="Optimization">
      <RibbonButton
        disabled={!hasActiveGraph ||
          (activeOptimizationId !== "cvss" && footholdHosts.length === 0) ||
          analysisRunning}
        onclick={() => onOptimize(activeOptimizationId)}
        ><Icon name="play" size={22} /><span>Optimize</span></RibbonButton
      >
      <Select
        label="Strategy"
        value={activeOptimizationId}
        disabled={!hasActiveGraph}
        onchange={(event) =>
          onOptimizationParamsChange({
            strategy: event.currentTarget
              .value as OptimizationParams["strategy"],
          })}
      >
        {#each availableOptimizationOptions as option (option.id)}
          <option value={option.id} disabled={option.disabled}>
            {option.title}
          </option>
        {/each}
      </Select>
      <NumberInput
        label="Budget"
        value={optimizationParams.budget}
        min={1}
        disabled={!hasActiveGraph}
        onchange={(budget) => onOptimizationParamsChange({ budget })}
      />
    </Ribbon.Section>
    {#if activeOptimizationId === "simulation_informed" || activeOptimizationId === "simulated_annealing"}
      <Ribbon.Section title="Simulation settings">
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
        <div class="dashboard-max-attempts-input">
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
        </div>
        <NumberInput
          label="Seed"
          value={optimizationParams.simulation_params.seed}
          disabled={optimizationParams.simulation_params.generate_seed}
          onchange={(seed) =>
            onOptimizationParamsChange({ simulation_params: { seed } })}
        />
        <Checkbox
          label="Random seed"
          checked={optimizationParams.simulation_params.generate_seed}
          onchange={(generate_seed) =>
            onOptimizationParamsChange({
              simulation_params: { generate_seed },
            })}
        />
      </Ribbon.Section>
    {:else if activeOptimizationId === "topology_segmentation"}
      <Ribbon.Section title="Topology segmentation">
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
      </Ribbon.Section>
    {/if}
  </Ribbon.Tab>
</Ribbon>

<style>
  .dashboard-max-attempts-input :global(.dashboard-number-input) {
    min-width: 8.5rem;
    width: 8.5rem;
  }
</style>
