<script lang="ts">
  import { Dialog } from "bits-ui";
  import type { AnalysisModel } from "./AnalysisModel.svelte";
  import type { OptimizationStrategy } from "../contract";
  import Checkbox from "../ui/Checkbox.svelte";
  import NumberInput from "../ui/NumberInput.svelte";
  import Select from "../ui/Select.svelte";
  import Slider from "../ui/Slider.svelte";
  import StrategyPicker from "./StrategyPicker.svelte";

  type OptimizationOption = {
    id: OptimizationStrategy;
    title: string;
  };

  interface Props {
    model: AnalysisModel;
    optimizationOptions: readonly OptimizationOption[];
  }

  let { model, optimizationOptions }: Props = $props();

  let controlsDisabled = $derived(model.isLoadingTarget || model.isRunning);
  let statusMessage = $derived(model.dialogStatusMessage);

  function handleOpenChange(open: boolean): void {
    if (!open && !controlsDisabled) model.closeDialog();
  }

  async function run(): Promise<void> {
    await model.run();
  }
</script>

<Dialog.Root open={model.open} onOpenChange={handleOpenChange}>
  {#if model.open}
    <Dialog.Portal>
      <Dialog.Overlay class="analysis-overlay" />
      <Dialog.Content class="analysis-dialog">
        <Dialog.Title>Analysis</Dialog.Title>
        <Dialog.Description>
          Run simulation and optimization for a saved graph.
        </Dialog.Description>

        <div class="analysis-body">
          <section class="analysis-section">
            <h2 class="analysis-section-title">Target graph</h2>
            <button
              class="analysis-target"
              type="button"
              disabled={controlsDisabled}
              aria-label={`Select target graph: ${model.targetLabel}`}
              onclick={() => model.openTargetPicker()}
            >
              {model.targetLabel}
            </button>
          </section>

          <section class="analysis-section">
            <Checkbox
              label="Simulation"
              checked={model.includeSimulation}
              disabled={controlsDisabled}
              onchange={(includeSimulation) =>
                (model.includeSimulation = includeSimulation)}
            />
            {#if model.includeSimulation}
              <div class="analysis-controls">
                <Select
                  label="Initial foothold"
                  value={model.workspace.simulationParams
                    .initial_foothold_node_id}
                  disabled={controlsDisabled ||
                    model.targetFootholdHosts.length === 0}
                  onchange={(event) =>
                    model.workspace.onSimulationParamsChange({
                      initial_foothold_node_id: event.currentTarget.value,
                    })}
                >
                  {#each model.targetFootholdHosts as host (host.id)}
                    <option value={host.id}>{host.name}</option>
                  {/each}
                </Select>
                <Slider
                  label="Monte Carlo trials"
                  min={1}
                  max={40000}
                  step={1000}
                  value={model.workspace.simulationParams.monte_carlo_trials}
                  disabled={controlsDisabled}
                  onchange={(monte_carlo_trials) =>
                    model.workspace.onSimulationParamsChange({
                      monte_carlo_trials,
                    })}
                />
                <Slider
                  label="Iterations per simulation"
                  min={1}
                  max={40000}
                  step={1000}
                  value={model.workspace.simulationParams.iterations_per_run}
                  disabled={controlsDisabled}
                  onchange={(iterations_per_run) =>
                    model.workspace.onSimulationParamsChange({
                      iterations_per_run,
                    })}
                />
                <NumberInput
                  label="Seed"
                  value={model.workspace.simulationParams.seed}
                  disabled={controlsDisabled ||
                    model.workspace.simulationParams.generate_seed}
                  onchange={(seed) =>
                    model.workspace.onSimulationParamsChange({ seed })}
                />
                <Checkbox
                  label="Random seed"
                  checked={model.workspace.simulationParams.generate_seed}
                  disabled={controlsDisabled}
                  onchange={(generate_seed) =>
                    model.workspace.onSimulationParamsChange({ generate_seed })}
                />
              </div>
            {/if}
          </section>

          <section class="analysis-section">
            <Checkbox
              label="Optimization"
              checked={model.includeOptimization}
              disabled={controlsDisabled}
              onchange={(includeOptimization) =>
                (model.includeOptimization = includeOptimization)}
            />
            {#if model.includeOptimization}
              <div class="analysis-controls">
                <StrategyPicker
                  options={optimizationOptions}
                  selectedStrategies={model.selectedStrategies}
                  hasFoothold={model.targetFootholdHosts.length > 0}
                  disabled={controlsDisabled}
                  onchange={(strategies) => model.setStrategies(strategies)}
                />
                <NumberInput
                  label="Budget"
                  value={model.workspace.optimizationParams.budget}
                  min={1}
                  disabled={controlsDisabled}
                  onchange={(budget) =>
                    model.workspace.onOptimizationParamsChange({ budget })}
                />
                {#if model.needsFoothold}
                  <Select
                    label="Initial foothold"
                    value={model.workspace.optimizationParams.simulation_params
                      .initial_foothold_node_id}
                    disabled={controlsDisabled ||
                      model.targetFootholdHosts.length === 0}
                    onchange={(event) =>
                      model.workspace.onOptimizationParamsChange({
                        simulation_params: {
                          initial_foothold_node_id: event.currentTarget.value,
                        },
                      })}
                  >
                    {#each model.targetFootholdHosts as host (host.id)}
                      <option value={host.id}>{host.name}</option>
                    {/each}
                  </Select>
                {/if}
                {#if model.needsSimulationSettings}
                  <Slider
                    label="Monte Carlo trials"
                    min={1}
                    max={40000}
                    step={1000}
                    value={model.workspace.optimizationParams.simulation_params
                      .monte_carlo_trials}
                    disabled={controlsDisabled}
                    onchange={(monte_carlo_trials) =>
                      model.workspace.onOptimizationParamsChange({
                        simulation_params: { monte_carlo_trials },
                      })}
                  />
                  <Slider
                    label="Iterations per simulation"
                    min={1}
                    max={40000}
                    step={1000}
                    value={model.workspace.optimizationParams.simulation_params
                      .iterations_per_run}
                    disabled={controlsDisabled}
                    onchange={(iterations_per_run) =>
                      model.workspace.onOptimizationParamsChange({
                        simulation_params: { iterations_per_run },
                      })}
                  />
                  <NumberInput
                    label="Maximum attempts"
                    value={model.workspace.optimizationParams.simulation_params
                      .max_attempts}
                    min={1}
                    disabled={controlsDisabled}
                    onchange={(max_attempts) =>
                      model.workspace.onOptimizationParamsChange({
                        simulation_params: { max_attempts },
                      })}
                  />
                  <NumberInput
                    label="Seed"
                    value={model.workspace.optimizationParams.simulation_params
                      .seed}
                    disabled={controlsDisabled ||
                      model.workspace.optimizationParams.simulation_params
                        .generate_seed}
                    onchange={(seed) =>
                      model.workspace.onOptimizationParamsChange({
                        simulation_params: { seed },
                      })}
                  />
                  <Checkbox
                    label="Random seed"
                    checked={model.workspace.optimizationParams
                      .simulation_params.generate_seed}
                    disabled={controlsDisabled}
                    onchange={(generate_seed) =>
                      model.workspace.onOptimizationParamsChange({
                        simulation_params: { generate_seed },
                      })}
                  />
                {/if}
              </div>
            {/if}
          </section>
        </div>

        {#if statusMessage}
          <p class="analysis-status" role="alert">{statusMessage}</p>
        {/if}

        <div class="analysis-actions">
          <button
            class="analysis-button"
            type="button"
            disabled={controlsDisabled}
            onclick={() => model.closeDialog()}
          >
            Cancel
          </button>
          <button
            class="analysis-button analysis-confirm"
            type="button"
            disabled={!model.canRun}
            onclick={run}
          >
            Run analysis
          </button>
        </div>
      </Dialog.Content>
    </Dialog.Portal>
  {/if}
</Dialog.Root>

<style>
  :global(.analysis-overlay) {
    position: fixed;
    z-index: 200;
    inset: 0;
    background: color-mix(in srgb, var(--ds-color-nav) 45%, transparent);
  }

  :global(.analysis-dialog) {
    position: fixed;
    z-index: 201;
    top: 50%;
    left: 50%;
    width: min(78rem, calc(100vw - 2rem));
    max-height: calc(100dvh - 2rem);
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr) auto auto;
    padding: var(--ds-space-4);
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-lg);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
    color: var(--ds-color-text);
    transform: translate(-50%, -50%);
  }

  :global(.analysis-dialog [data-dialog-title]) {
    margin: 0;
    font-size: var(--ds-text-xl);
  }

  :global(.analysis-dialog [data-dialog-description]) {
    margin: var(--ds-space-2) 0 0;
    color: var(--ds-color-text-secondary);
  }

  .analysis-body {
    display: grid;
    gap: var(--ds-space-3);
    min-height: 0;
    margin-top: var(--ds-space-4);
    overflow: auto;
  }

  .analysis-section {
    padding: var(--ds-space-3);
    border: 1px solid var(--ds-color-border-soft);
    border-radius: var(--ds-radius-md);
  }

  .analysis-section-title {
    margin: 0 0 var(--ds-space-2);
    font-size: var(--ds-text-base);
  }

  .analysis-target {
    width: 100%;
    min-height: var(--ds-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-surface);
    color: inherit;
    text-align: left;
  }

  .analysis-controls {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--ds-space-2);
    margin-top: var(--ds-space-2);
  }

  .analysis-status {
    margin: var(--ds-space-3) 0 0;
    padding: var(--ds-space-2) var(--ds-space-3);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-warning-bg);
    color: var(--ds-color-warning-text);
    font-size: var(--ds-text-sm);
  }

  .analysis-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--ds-space-2);
    margin-top: var(--ds-space-4);
  }

  .analysis-button {
    min-height: var(--ds-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-surface);
    color: inherit;
  }

  .analysis-confirm {
    border-color: var(--ds-color-accent);
    background: var(--ds-color-accent);
    color: var(--ds-color-paper);
  }

  .analysis-target:disabled,
  .analysis-button:disabled {
    cursor: default;
    opacity: 0.55;
  }

  @media (min-width: 64rem) {
    .analysis-body {
      grid-template-columns: repeat(3, minmax(0, 1fr));
      align-items: start;
    }

    .analysis-controls {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 30rem) {
    :global(.analysis-dialog) {
      width: calc(100vw - 1rem);
      max-height: calc(100dvh - 1rem);
      padding: var(--ds-space-3);
    }

    .analysis-controls {
      grid-template-columns: 1fr;
    }
  }
</style>
