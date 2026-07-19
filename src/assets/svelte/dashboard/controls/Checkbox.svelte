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

<label class="dashboard-checkbox">
  <input
    {...attributes}
    class={["dashboard-checkbox-input", className]}
    type="checkbox"
    {checked}
    onchange={handleChange}
  />
  <span class="dashboard-checkbox-indicator" aria-hidden="true"></span>
  {#if children}
    <span class="dashboard-checkbox-label">{@render children()}</span>
  {/if}
</label>

<style>
  .dashboard-checkbox {
    display: inline-flex;
    align-items: center;
    gap: var(--ds-space-2);
    min-height: var(--ds-control-height);
    padding: 0.1875rem;
    color: var(--ds-color-text);
  }

  .dashboard-checkbox-input {
    position: absolute;
    width: 1px;
    height: 1px;
    margin: -1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
    white-space: nowrap;
    border: 0;
  }

  .dashboard-checkbox-indicator {
    display: grid;
    place-items: center;
    width: 1rem;
    height: 1rem;
    flex: none;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-paper);
  }

  .dashboard-checkbox-input:checked + .dashboard-checkbox-indicator {
    border-color: var(--ds-color-accent);
    background: var(--ds-color-accent);
  }

  .dashboard-checkbox-input:checked + .dashboard-checkbox-indicator::after {
    width: 0.5rem;
    height: 0.25rem;
    border-bottom: 2px solid var(--ds-color-on-dark);
    border-left: 2px solid var(--ds-color-on-dark);
    transform: rotate(-45deg) translate(0.0625rem, -0.0625rem);
    content: "";
  }

  .dashboard-checkbox-input:focus-visible + .dashboard-checkbox-indicator {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 2px;
  }

  .dashboard-checkbox:has(.dashboard-checkbox-input:disabled) {
    color: var(--ds-color-text-faint);
    cursor: not-allowed;
  }

  .dashboard-checkbox-input:disabled + .dashboard-checkbox-indicator {
    background: var(--ds-color-surface);
  }
</style>
