<script lang="ts">
  import type { Snippet } from "svelte";
  import type { HTMLInputAttributes } from "svelte/elements";

  interface Props extends Omit<HTMLInputAttributes, "type" | "checked"> {
    checked?: boolean;
    children?: Snippet;
  }

  let {
    checked = $bindable(false),
    children,
    class: className,
    onchange,
    ...attributes
  }: Props = $props();

  function handleChange(event: Event & { currentTarget: HTMLInputElement }) {
    onchange?.(event);
    checked = event.currentTarget.checked;
  }
</script>

<label class="dashboard-radio-button">
  <input
    {...attributes}
    class={["dashboard-radio-button-input", className]}
    type="radio"
    {checked}
    onchange={handleChange}
  />
  <span class="dashboard-radio-button-indicator" aria-hidden="true"></span>
  {#if children}
    <span class="dashboard-radio-button-label">{@render children()}</span>
  {/if}
</label>

<style>
  .dashboard-radio-button {
    display: inline-flex;
    align-items: center;
    gap: var(--ds-space-2);
    min-height: var(--ds-control-height);
    color: var(--ds-color-text);
  }

  .dashboard-radio-button-input {
    position: absolute;
    width: 1px;
    height: 1px;
    margin: -1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
    white-space: nowrap;
    border: 0;
  }

  .dashboard-radio-button-indicator {
    display: grid;
    place-items: center;
    width: 1rem;
    height: 1rem;
    flex: none;
    border: 1px solid var(--ds-color-border);
    border-radius: 50%;
    background: var(--ds-color-paper);
  }

  .dashboard-radio-button-input:checked + .dashboard-radio-button-indicator {
    border-color: var(--ds-color-accent);
  }

  .dashboard-radio-button-input:checked
    + .dashboard-radio-button-indicator::after {
    width: 0.5rem;
    height: 0.5rem;
    border-radius: 50%;
    background: var(--ds-color-accent);
    content: "";
  }

  .dashboard-radio-button-input:focus-visible
    + .dashboard-radio-button-indicator {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 2px;
  }

  .dashboard-radio-button:has(.dashboard-radio-button-input:disabled) {
    color: var(--ds-color-text-faint);
    cursor: not-allowed;
  }

  .dashboard-radio-button-input:disabled + .dashboard-radio-button-indicator {
    background: var(--ds-color-surface);
  }
</style>
