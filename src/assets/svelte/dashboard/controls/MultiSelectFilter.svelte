<script lang="ts">
  import { Checkbox, Popover } from "bits-ui";

  export interface MultiSelectFilterOption {
    value: string;
    label: string;
  }

  interface Props {
    label: string;
    options: readonly MultiSelectFilterOption[];
    selectedValues: readonly string[];
    onchange: (values: string[]) => void;
    disabled?: boolean;
  }

  let {
    label,
    options,
    selectedValues,
    onchange,
    disabled = false,
  }: Props = $props();

  const selectedCount = $derived(selectedValues.length);
</script>

<Popover.Root>
  <Popover.Trigger
    class="multi-select-filter-trigger"
    aria-label={`${label} filter, ${selectedCount} selected`}
    {disabled}
  >
    <svg
      aria-hidden="true"
      viewBox="0 0 16 16"
      width="14"
      height="14"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"><path d="M3 5h10l-3 3v3l-2 1v-4z" /></svg
    >
    {#if selectedCount > 0}
      <span class="multi-select-filter-count" aria-hidden="true"
        >{selectedCount}</span
      >
    {/if}
  </Popover.Trigger>
  <Popover.Portal>
    <Popover.Content
      class="multi-select-filter-content"
      side="bottom"
      align="start"
      sideOffset={4}
    >
      <Checkbox.Group
        class="multi-select-filter-options"
        value={[...selectedValues]}
        onValueChange={onchange}
        aria-label={`${label} filters`}
      >
        {#each options as option (option.value)}
          <Checkbox.Root
            class="multi-select-filter-option"
            value={option.value}
            {disabled}
          >
            <span class="multi-select-filter-indicator" aria-hidden="true"
            ></span>
            <span>{option.label}</span>
          </Checkbox.Root>
        {/each}
      </Checkbox.Group>
    </Popover.Content>
  </Popover.Portal>
</Popover.Root>

<style>
  :global(.multi-select-filter-trigger) {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    min-height: 1.75rem;
    padding: 0 0.375rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-paper);
    color: var(--ui-color-text-secondary);
    font: inherit;
    font-size: var(--ui-text-xs);
    font-weight: 600;
    white-space: nowrap;
  }

  :global(.multi-select-filter-trigger:hover:not(:disabled)) {
    border-color: var(--ui-color-accent);
  }

  :global(.multi-select-filter-trigger:focus-visible),
  :global(.multi-select-filter-option:focus-visible) {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: 2px;
  }

  :global(.multi-select-filter-trigger:disabled) {
    color: var(--ui-color-text-faint);
    cursor: default;
  }

  .multi-select-filter-count {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 1rem;
    height: 1rem;
    padding: 0 0.1875rem;
    border-radius: 999px;
    background: var(--ui-color-accent);
    color: var(--ui-color-on-dark);
    font-size: 0.6875rem;
    line-height: 1;
  }

  :global(.multi-select-filter-content) {
    z-index: 100;
    min-width: 12rem;
    max-width: min(20rem, calc(100vw - 2rem));
    max-height: min(18rem, calc(100dvh - 2rem));
    overflow: auto;
    padding: var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
  }

  :global(.multi-select-filter-options) {
    display: grid;
    gap: var(--ui-space-1);
  }

  :global(.multi-select-filter-option) {
    display: flex;
    align-items: center;
    gap: var(--ui-space-2);
    width: 100%;
    min-width: 0;
    padding: var(--ui-space-2);
    border: 0;
    border-radius: var(--ui-radius-sm);
    background: transparent;
    color: var(--ui-color-text);
    font: inherit;
    font-size: var(--ui-text-sm);
    text-align: start;
    cursor: pointer;
  }

  :global(.multi-select-filter-option:disabled) {
    color: var(--ui-color-text-faint);
    cursor: default;
  }

  .multi-select-filter-indicator {
    flex: none;
    width: 1.125rem;
    height: 1.125rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
  }

  :global(.multi-select-filter-option[data-state="checked"])
    .multi-select-filter-indicator {
    border-color: var(--ui-color-accent);
    background: var(--ui-color-accent);
  }

  .multi-select-filter-indicator {
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  :global(.multi-select-filter-option[data-state="checked"])
    .multi-select-filter-indicator::after {
    width: 0.375rem;
    height: 0.625rem;
    border-right: 2px solid var(--ui-color-paper);
    border-bottom: 2px solid var(--ui-color-paper);
    content: "";
    transform: rotate(45deg) translate(-1px, -1px);
  }
</style>
