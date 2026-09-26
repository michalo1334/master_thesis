<script lang="ts">
  import type { OptimizationParams } from "../../contracts.generated/optimization";
  import type { SimulationParams } from "../../contracts.generated/simulation";
  import RibbonButton from "../../ui-kit/primitives/RibbonButton.svelte";
  import Icon from "../../ui-kit/primitives/Icon.svelte";
  import { Ribbon } from "../../ui-kit/layout";
  import Slider from "../../ui-kit/primitives/Slider.svelte";
  import type { OptimizationParamsChange } from "../contract";
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
    downloadResultsHref?: string;
  }

  let {
    hasActiveGraph,
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
    downloadResultsHref = undefined,
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
      <RibbonButton
        disabled={!downloadResultsHref}
        onclick={() => {
          if (!downloadResultsHref) return;
          const anchor = document.createElement("a");
          anchor.href = downloadResultsHref;
          anchor.download = "";
          document.body.appendChild(anchor);
          anchor.click();
          anchor.remove();
        }}
        aria-label="Download results"
        ><Icon name="download" size={22} /><span>Download results</span
        ></RibbonButton
      >
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="Simulation">
    <Ribbon.Section title="Attack model">
      <RibbonButton
        onclick={onRunSimulation}
        disabled={!hasActiveGraph || footholdHosts.length === 0}
        ><Icon name="play" size={22} /><span>Simulate</span></RibbonButton
      >
    </Ribbon.Section>
    <Ribbon.Section title="Standalone simulation">
      <Select
        label="Initial foothold"
        value={simulationParams.initial_foothold_node_id}
        disabled={!hasActiveGraph || footholdHosts.length === 0}
        options={footholdHosts.map((host) => ({
          value: host.id,
          label: host.name,
        }))}
        onchange={(initial_foothold_node_id) =>
          onSimulationParamsChange({ initial_foothold_node_id })}
      />
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
          (activeOptimizationId !== "cvss" && footholdHosts.length === 0)}
        onclick={() => onOptimize(activeOptimizationId)}
        ><Icon name="play" size={22} /><span>Optimize</span></RibbonButton
      >
      <Select
        label="Strategy"
        value={activeOptimizationId}
        disabled={!hasActiveGraph}
        options={availableOptimizationOptions.map((option) => ({
          value: option.id,
          label: option.title,
          disabled: option.disabled,
        }))}
        onchange={(strategy) =>
          onOptimizationParamsChange({
            strategy: strategy as OptimizationParams["strategy"],
          })}
      />
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
          options={footholdHosts.map((host) => ({
            value: host.id,
            label: host.name,
          }))}
          onchange={(initial_foothold_node_id) =>
            onOptimizationParamsChange({
              simulation_params: { initial_foothold_node_id },
            })}
        />
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
          options={footholdHosts.map((host) => ({
            value: host.id,
            label: host.name,
          }))}
          onchange={(initial_foothold_node_id) =>
            onOptimizationParamsChange({
              simulation_params: { initial_foothold_node_id },
            })}
        />
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
