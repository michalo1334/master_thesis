<script lang="ts">
  import { DropdownMenu } from "bits-ui";
  import type { Snippet } from "svelte";
  import type { HTMLButtonAttributes } from "svelte/elements";
  import Icon from "./Icon.svelte";
  import type { IconName } from "../types";

  export interface SplitButtonItem {
    label: string;
    icon?: IconName;
    onclick?: (event: MouseEvent) => void;
    disabled?: boolean;
  }

  interface Props extends HTMLButtonAttributes {
    items: SplitButtonItem[];
    children?: Snippet;
  }

  let {
    items,
    children,
    class: className,
    type,
    ...attributes
  }: Props = $props();
</script>

<div class="dashboard-split-button" role="group" aria-label="Split button">
  <button {...attributes} class={["dashboard-split-button-primary", className]} type={type ?? "button"}>
    {@render children?.()}
  </button>
  <DropdownMenu.Root>
    <DropdownMenu.Trigger class="dashboard-split-button-trigger" aria-label="More actions">
      <Icon name="chevron-down" size={16} />
    </DropdownMenu.Trigger>
    <DropdownMenu.Portal>
      <DropdownMenu.Content class="dashboard-split-button-menu" side="bottom" sideOffset={4} align="start">
        {#each items as item (item.label)}
          <DropdownMenu.Item disabled={item.disabled} onclick={item.onclick}>
            {#if item.icon}
              <Icon name={item.icon} size={16} />
            {/if}
            <span>{item.label}</span>
          </DropdownMenu.Item>
        {/each}
      </DropdownMenu.Content>
    </DropdownMenu.Portal>
  </DropdownMenu.Root>
</div>

<style>
  .dashboard-split-button {
    display: inline-flex;
    align-items: stretch;
    min-height: 3.875rem;
    border: 1px solid transparent;
    border-radius: var(--ds-radius-md);
    --dashboard-icon-color: #315f9a;
  }

  .dashboard-split-button:has(button:not(:disabled)):hover {
    border-color: #b9d5f8;
    background: var(--ds-color-accent-soft);
  }

  .dashboard-split-button-primary,
  .dashboard-split-button-trigger {
    border: 0;
    background: transparent;
  }

  .dashboard-split-button-primary {
    min-width: 3.125rem;
    padding: 0.3125rem 0.4375rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--ds-space-1);
  }

  .dashboard-split-button-trigger {
    width: 1.375rem;
    padding: 0;
    border-left: 1px solid transparent;
    display: grid;
    place-items: center;
  }

  .dashboard-split-button:hover .dashboard-split-button-trigger,
  .dashboard-split-button:has(.dashboard-split-button-trigger[data-state="open"]) .dashboard-split-button-trigger {
    border-left-color: #b9d5f8;
  }

  :global(.dashboard-split-button-menu) {
    z-index: 100;
    min-width: 11rem;
    padding: 0.25rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
  }

  :global(.dashboard-split-button-menu [role="menuitem"]) {
    width: 100%;
    min-height: var(--ds-control-height);
    padding: 0.25rem 0.5rem;
    border-radius: var(--ds-radius-sm);
    display: flex;
    align-items: center;
    gap: var(--ds-space-2);
    outline: 0;
  }

  :global(.dashboard-split-button-menu [role="menuitem"][data-highlighted]) {
    background: var(--ds-color-accent-soft);
  }
</style>
