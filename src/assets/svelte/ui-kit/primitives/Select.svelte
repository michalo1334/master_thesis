<script lang="ts">
  import { Select } from "bits-ui";

  interface SelectOption {
    value: string;
    label: string;
    disabled?: boolean;
  }

  interface Props {
    options: readonly SelectOption[];
    label?: string;
    value?: string;
    placeholder?: string;
    disabled?: boolean;
    onchange?: (value: string) => void;
    class?: string;
    "aria-label"?: string;
    "aria-invalid"?: "true";
    "aria-describedby"?: string;
  }

  const generatedId = $props.id();

  let {
    options,
    label = undefined,
    value = $bindable(""),
    placeholder = "Select…",
    disabled = false,
    onchange = undefined,
    class: className = undefined,
    "aria-label": ariaLabel = undefined,
    "aria-invalid": ariaInvalid = undefined,
    "aria-describedby": ariaDescribedBy = undefined,
  }: Props = $props();

  const labelId = `${generatedId}-label`;
  let items = $derived(
    options.map((option) => ({
      value: option.value,
      label: option.label,
      disabled: option.disabled ?? false,
    })),
  );
</script>

<div class="dashboard-select" class:disabled>
  {#if label}
    <span class="dashboard-select-label" id={labelId}>{label}</span>
  {/if}
  <Select.Root
    type="single"
    bind:value
    {disabled}
    {items}
    onValueChange={(next) => onchange?.(next)}
  >
    <Select.Trigger
      id={generatedId}
      class={["dashboard-select-control", className]}
      aria-labelledby={label ? labelId : undefined}
      aria-label={ariaLabel}
      aria-invalid={ariaInvalid}
      aria-describedby={ariaDescribedBy}
    >
      <Select.Value {placeholder} />
      <span class="dashboard-select-caret" aria-hidden="true">▾</span>
    </Select.Trigger>
    <Select.Portal>
      <Select.Content class="dashboard-select-content" sideOffset={4}>
        <Select.Viewport class="dashboard-select-viewport">
          {#each options as option (option.value)}
            <Select.Item
              value={option.value}
              label={option.label}
              disabled={option.disabled ?? false}
              aria-disabled={option.disabled ? "true" : undefined}
              class="dashboard-select-item"
            >
              {option.label}
            </Select.Item>
          {/each}
        </Select.Viewport>
      </Select.Content>
    </Select.Portal>
  </Select.Root>
</div>

<style>
  .dashboard-select {
    display: grid;
    align-content: center;
    gap: 0.1875rem;
    min-width: 8.5rem;
    padding: 0.1875rem;
  }

  .dashboard-select.disabled {
    opacity: 0.5;
  }

  .dashboard-select-label {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    font-weight: 600;
  }

  :global(.dashboard-select-control) {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    width: 100%;
    min-height: var(--ui-control-height);
    padding: 0.1875rem 0.5rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    color: var(--ui-color-text);
    text-align: start;
  }

  :global(.dashboard-select-control:not(:disabled):hover) {
    border-color: var(--ui-color-accent);
  }

  :global(.dashboard-select-control:focus-visible) {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: 1px;
  }

  :global(.dashboard-select-control:disabled) {
    color: var(--ui-color-text-faint);
    background: var(--ui-color-surface);
  }

  :global(.dashboard-select-control[data-placeholder]) {
    color: var(--ui-color-text-secondary);
  }

  .dashboard-select-caret {
    flex: none;
    font-size: var(--ui-text-xs);
  }

  :global(.dashboard-select-content) {
    z-index: 1000;
    min-width: var(--bits-select-anchor-width, 8.5rem);
    max-height: var(--bits-select-content-available-height, 18rem);
    overflow: hidden;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
  }

  :global(.dashboard-select-viewport) {
    padding: 0.1875rem;
  }

  :global(.dashboard-select-item) {
    padding: 0.25rem 0.5rem;
    border-radius: var(--ui-radius-sm);
    color: var(--ui-color-text);
    cursor: pointer;
  }

  :global(.dashboard-select-item[data-highlighted]) {
    background: var(--ui-color-accent-soft);
  }

  :global(.dashboard-select-item[data-disabled]) {
    color: var(--ui-color-text-faint);
    cursor: default;
  }
</style>
