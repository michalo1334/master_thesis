<script lang="ts">
  import { Checkbox } from "bits-ui";

  interface Props {
    label: string;
    checked?: boolean;
    disabled?: boolean;
    onchange?: (checked: boolean) => void;
  }

  let {
    label,
    checked = $bindable(false),
    disabled = false,
    onchange,
  }: Props = $props();

  const id = $props.id();
  const checkboxId = `${id}-checkbox`;

  function handleCheckedChange(newChecked: boolean) {
    onchange?.(newChecked);
  }
</script>

<div class="dashboard-checkbox" class:disabled>
  <Checkbox.Root
    bind:checked
    id={checkboxId}
    {disabled}
    onCheckedChange={handleCheckedChange}
    class="dashboard-checkbox-root"
  >
    <span class="dashboard-checkbox-indicator" aria-hidden="true"></span>
  </Checkbox.Root>
  <label class="dashboard-checkbox-label" for={checkboxId}>{label}</label>
</div>

<style>
  .dashboard-checkbox {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    min-width: 6.5rem;
    padding: 0.1875rem;
  }

  .dashboard-checkbox.disabled {
    opacity: 0.5;
    pointer-events: none;
  }

  :global(.dashboard-checkbox-root) {
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1.125rem;
    height: 1.125rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-paper);
  }

  :global(.dashboard-checkbox-root:hover:not(:disabled)) {
    border-color: var(--ds-color-accent);
  }

  :global(.dashboard-checkbox-root:focus-visible) {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 2px;
  }

  .dashboard-checkbox-indicator {
    display: block;
    width: 0.375rem;
    height: 0.625rem;
    border-right: 2px solid transparent;
    border-bottom: 2px solid transparent;
    transform: rotate(45deg) translate(-1px, -1px);
    transition: border-color 0.1s;
  }

  :global(.dashboard-checkbox-root[data-state="checked"]) {
    border-color: var(--ds-color-accent);
    background: var(--ds-color-accent);
  }

  :global(.dashboard-checkbox-root[data-state="checked"])
    .dashboard-checkbox-indicator {
    border-color: var(--ds-color-paper);
  }

  :global(.dashboard-checkbox-root[data-state="indeterminate"])
    .dashboard-checkbox-indicator {
    width: 0.5rem;
    height: 0;
    border-right: 0;
    border-bottom: 2px solid var(--ds-color-paper);
    transform: rotate(0) translate(0, 0);
  }

  :global(.dashboard-checkbox-root[data-state="indeterminate"]) {
    border-color: var(--ds-color-accent);
    background: var(--ds-color-accent);
  }

  .dashboard-checkbox-label {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-xs);
    font-weight: 600;
    white-space: nowrap;
    user-select: none;
  }
</style>
