<script lang="ts">
  import { Slider } from "bits-ui";

  interface Props {
    label: string;
    value?: number;
    min?: number;
    max?: number;
    step?: number;
    disabled?: boolean;
    onchange?: (value: number) => void;
  }

  let {
    label,
    value = $bindable(0),
    min = 0,
    max = 100,
    step = 1,
    disabled = false,
    onchange,
  }: Props = $props();

  const id = $props.id();
  const labelId = `${id}-label`;
  const inputId = `${id}-input`;
  let sliderSteps = $derived(getSliderSteps(value));

  function getSliderSteps(currentValue: number) {
    const firstStep = Math.ceil(min / step);
    const lastStep = Math.floor(max / step);
    const steps = [min];

    for (let index = firstStep; index <= lastStep; index++) {
      steps.push(roundToStepPrecision(index * step));
    }

    if (isValidManualValue(currentValue)) {
      steps.push(currentValue);
    }

    return [...new Set(steps)];
  }

  function roundToStepPrecision(nextValue: number) {
    const precision = step.toString().split(".")[1]?.length ?? 0;
    return Number(nextValue.toFixed(precision));
  }

  function handleValueCommit(v: number) {
    onchange?.(v);
  }

  function isValidManualValue(nextValue: number) {
    return Number.isFinite(nextValue) && nextValue >= min && nextValue <= max;
  }

  function handleManualValueCommit(event: Event) {
    const input = event.currentTarget as HTMLInputElement;
    const nextValue = input.valueAsNumber;

    if (!isValidManualValue(nextValue)) {
      input.value = value === undefined ? "" : String(value);
      return;
    }

    value = nextValue;
    onchange?.(nextValue);
  }
</script>

<div class="dashboard-slider" class:disabled>
  <label class="dashboard-slider-label" for={inputId} id={labelId}
    >{label}</label
  >
  <div class="dashboard-slider-controls">
    <Slider.Root
      type="single"
      bind:value
      {min}
      {max}
      step={sliderSteps}
      {disabled}
      onValueCommit={handleValueCommit}
      aria-labelledby={labelId}
      class="ds-slider-root"
    >
      <span class="ds-slider-track">
        <Slider.Range class="ds-slider-range" />
      </span>
      <Slider.Thumb index={0} class="ds-slider-thumb" />
    </Slider.Root>
    <input
      class="dashboard-slider-value"
      id={inputId}
      type="number"
      {value}
      {min}
      {max}
      step="any"
      {disabled}
      onchange={handleManualValueCommit}
    />
  </div>
</div>

<style>
  .dashboard-slider {
    display: grid;
    align-content: center;
    gap: 0.1875rem;
    min-width: 6.5rem;
    padding: 0.1875rem;
  }

  .dashboard-slider-label {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-xs);
    font-weight: 600;
    white-space: nowrap;
  }

  .dashboard-slider-controls {
    display: flex;
    align-items: center;
    gap: 0.375rem;
  }

  .dashboard-slider-value {
    flex: none;
    width: 3.5rem;
    min-width: 0;
    padding: 0;
    border: 0;
    background: transparent;
    appearance: textfield;
    text-align: right;
    color: var(--ds-color-text);
    font-size: var(--ds-text-xs);
    font-variant-numeric: tabular-nums;
  }

  .dashboard-slider-value::-webkit-inner-spin-button,
  .dashboard-slider-value::-webkit-outer-spin-button {
    margin: 0;
    appearance: none;
  }

  .dashboard-slider-value:focus-visible {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 2px;
  }

  .dashboard-slider-value:disabled {
    cursor: default;
  }

  .dashboard-slider.disabled {
    opacity: 0.5;
    pointer-events: none;
  }

  :global(.ds-slider-root) {
    flex: 1;
    min-width: 0;
    position: relative;
    display: flex;
    align-items: center;
    height: var(--ds-control-height);
    touch-action: none;
  }

  :global(.ds-slider-track) {
    position: relative;
    width: 100%;
    height: 4px;
    background: var(--ds-color-border);
    border-radius: 9999px;
  }

  :global(.ds-slider-range) {
    height: 100%;
    background: var(--ds-color-accent);
    border-radius: 9999px;
  }

  :global(.ds-slider-thumb) {
    display: block;
    width: 16px;
    height: 16px;
    background: var(--ds-color-accent);
    border-radius: 50%;
    top: 50%;
    cursor: grab;
  }

  :global(.ds-slider-thumb:focus-visible) {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 2px;
  }
</style>
