<script lang="ts">
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
    min = undefined,
    max = undefined,
    step = 1,
    disabled = false,
    onchange,
  }: Props = $props();

  const id = $props.id();
  const inputId = `${id}-input`;

  function isManualValue(nextValue: number) {
    if (!Number.isFinite(nextValue)) return false;
    if (min !== undefined && nextValue < min) return false;
    if (max !== undefined && nextValue > max) return false;
    return true;
  }

  function handleChange(event: Event) {
    const input = event.currentTarget as HTMLInputElement;
    const nextValue = input.valueAsNumber;

    if (!isManualValue(nextValue)) {
      input.value = value === undefined ? "" : String(value);
      return;
    }

    value = nextValue;
    onchange?.(nextValue);
  }
</script>

<div class="dashboard-number-input" class:disabled>
  <label class="dashboard-number-input-label" for={inputId}>{label}</label>
  <input
    class="dashboard-number-input-control"
    id={inputId}
    type="number"
    {value}
    {min}
    {max}
    {step}
    {disabled}
    onchange={handleChange}
  />
</div>

<style>
  .dashboard-number-input {
    display: grid;
    align-content: center;
    gap: 0.1875rem;
    min-width: 4.5rem;
    width: 4.5rem;
    padding: 0.1875rem;
  }

  .dashboard-number-input.disabled {
    opacity: 0.5;
    pointer-events: none;
  }

  .dashboard-number-input-label {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-xs);
    font-weight: 600;
    white-space: nowrap;
  }

  .dashboard-number-input-control {
    width: 100%;
    min-width: 0;
    min-height: var(--ds-control-height);
    padding: 0.1875rem 0.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    color: var(--ds-color-text);
    font-size: var(--ds-text-xs);
    font-variant-numeric: tabular-nums;
  }

  .dashboard-number-input-control::-webkit-inner-spin-button,
  .dashboard-number-input-control::-webkit-outer-spin-button {
    margin: 0;
    appearance: none;
  }

  .dashboard-number-input-control:not(:disabled):hover {
    border-color: var(--ds-color-accent);
  }

  .dashboard-number-input-control:focus-visible {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 2px;
  }

  .dashboard-number-input-control:disabled {
    color: var(--ds-color-text-faint);
    background: var(--ds-color-surface);
    cursor: default;
  }
</style>
