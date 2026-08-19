<script lang="ts">
  import { DropdownMenu } from "bits-ui";
  import Icon from "./Icon.svelte";

  export interface SplitButtonOption {
    id: string;
    icon?: string;
    title: string;
    disabled?: boolean;
  }

  interface Props {
    options: readonly SplitButtonOption[];
    activeId?: string;
    onSelect: (id: string) => void;
    disabled?: boolean;
    variant?: "large" | "small";
    ariaLabel?: string;
    class?: string;
  }

  let {
    options,
    activeId = undefined,
    onSelect,
    disabled = false,
    variant = "large",
    ariaLabel = undefined,
    class: className,
  }: Props = $props();

  let activeOption = $derived(
    options.find((option) => option.id === activeId) ?? options[0],
  );

  let iconSize = $derived(variant === "small" ? 18 : 22);

  function handleMainClick() {
    if (disabled || activeOption.disabled) return;
    onSelect(activeOption.id);
  }
</script>

{#if activeOption}
  <div
    class={[
      "dashboard-split-button",
      variant === "small" && "dashboard-split-button-small",
      className,
    ]}
  >
    <button
      type="button"
      class="dashboard-split-button-main"
      onclick={handleMainClick}
      disabled={disabled || activeOption.disabled}
      aria-label={ariaLabel}
      title={activeOption.title}
    >
      {#if activeOption.icon}
        <Icon name={activeOption.icon} size={iconSize} />
      {/if}
      <span>{activeOption.title}</span>
    </button>
    <DropdownMenu.Root>
      <DropdownMenu.Trigger
        class="dashboard-split-button-chevron"
        {disabled}
        aria-label="More options"
      >
        <Icon name="chevron-down" size={iconSize === 22 ? 16 : 14} />
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          class="dashboard-split-button-menu"
          side="bottom"
          sideOffset={2}
          align="end"
        >
          {#each options as option (option.id)}
            <DropdownMenu.Item
              disabled={option.disabled}
              onclick={() => onSelect(option.id)}
            >
              {#if option.icon}
                <Icon name={option.icon} size={16} />
              {/if}
              <span>{option.title}</span>
            </DropdownMenu.Item>
          {/each}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  </div>
{/if}

<style>
  .dashboard-split-button {
    display: inline-flex;
    align-items: stretch;
    min-width: 3.125rem;
    min-height: 3.875rem;
    border: 1px solid transparent;
    border-radius: var(--ui-radius-md);
    background: transparent;
    color: var(--ui-color-text);
    --dashboard-icon-color: var(--ui-color-accent);
  }

  .dashboard-split-button:not(:has(button:disabled)):hover,
  .dashboard-split-button:global(:has([data-state="open"])) {
    background: var(--ui-color-accent-soft);
    border-color: var(--ui-color-accent-soft);
  }

  .dashboard-split-button-small {
    min-width: 4.625rem;
    min-height: var(--ui-control-height);
  }

  .dashboard-split-button-main,
  .dashboard-split-button :global(.dashboard-split-button-chevron) {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--ui-space-1);
    padding: 0.3125rem 0.4375rem;
    border: 0;
    background: transparent;
    color: inherit;
    font: inherit;
  }

  .dashboard-split-button-main {
    flex: 1 1 auto;
    flex-direction: column;
    min-width: 0;
  }

  .dashboard-split-button-small .dashboard-split-button-main {
    flex-direction: row;
    justify-content: flex-start;
  }

  .dashboard-split-button-main > span,
  .dashboard-split-button-small .dashboard-split-button-main > span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .dashboard-split-button :global(.dashboard-split-button-chevron) {
    flex: none;
    align-self: stretch;
    width: 1.25rem;
    border-left: 1px solid transparent;
    cursor: pointer;
  }

  .dashboard-split-button:not(:has(button:disabled)):hover
    :global(.dashboard-split-button-chevron),
  .dashboard-split-button:global(:has([data-state="open"]))
    :global(.dashboard-split-button-chevron) {
    border-left-color: color-mix(
      in srgb,
      var(--ui-color-accent) 35%,
      transparent
    );
  }

  .dashboard-split-button-main:disabled,
  .dashboard-split-button :global(.dashboard-split-button-chevron:disabled) {
    cursor: default;
  }

  :global(.dashboard-split-button-menu) {
    z-index: 100;
    min-width: 11rem;
    padding: 0.25rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
  }

  :global(.dashboard-split-button-menu [role="menuitem"]) {
    min-height: var(--ui-control-height);
    padding: 0.25rem 0.5rem;
    border-radius: var(--ui-radius-sm);
    display: flex;
    align-items: center;
    gap: var(--ui-space-2);
    outline: 0;
    cursor: pointer;
  }

  :global(.dashboard-split-button-menu [role="menuitem"][data-highlighted]) {
    background: var(--ui-color-accent-soft);
  }

  :global(.dashboard-split-button-menu [role="menuitem"][data-disabled]) {
    color: var(--ui-color-text-faint);
    cursor: default;
  }
</style>
