<script lang="ts">
  import type { Snippet } from "svelte";
  import type { HTMLSelectAttributes } from "svelte/elements";

  interface Props extends Omit<HTMLSelectAttributes, "value"> {
    label?: string;
    value?: string;
    children?: Snippet;
  }

  const generatedId = $props.id();

  let {
    label,
    value = $bindable(""),
    children,
    class: className,
    id = generatedId,
    ...attributes
  }: Props = $props();
</script>

<div class="dashboard-select">
  {#if label}
    <label class="dashboard-select-label" for={id}>{label}</label>
  {/if}
  <select
    {...attributes}
    class={["dashboard-select-control", className]}
    {id}
    bind:value
  >
    {@render children?.()}
  </select>
</div>

<style>
  .dashboard-select {
    display: grid;
    align-content: center;
    gap: 0.1875rem;
    min-width: 8.5rem;
    padding: 0.1875rem;
  }

  .dashboard-select-label {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    font-weight: 600;
  }

  .dashboard-select-control {
    width: 100%;
    min-height: var(--ui-control-height);
    padding: 0.1875rem 1.75rem 0.1875rem 0.5rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }

  .dashboard-select-control:not(:disabled):hover {
    border-color: var(--ui-color-accent);
  }

  .dashboard-select-control:disabled {
    color: var(--ui-color-text-faint);
    background: var(--ui-color-surface);
  }
</style>
