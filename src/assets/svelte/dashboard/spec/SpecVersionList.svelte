<script lang="ts">
  import type { SpecListItem } from "./spec.types";

  interface Props {
    heading: string;
    addLabel: string;
    items: readonly SpecListItem[];
    selectedId: string | null;
    emptyMessage: string;
    isBusy: boolean;
    onAdd: () => void;
    onSelect: (id: string) => void;
  }

  let {
    heading,
    addLabel,
    items,
    selectedId,
    emptyMessage,
    isBusy,
    onAdd,
    onSelect,
  }: Props = $props();
</script>

<div class="spec-list-pane">
  <div class="spec-pane-header">
    <h2 class="spec-pane-title">{heading}</h2>
    <button class="spec-button" type="button" disabled={isBusy} onclick={onAdd}>
      {addLabel}
    </button>
  </div>
  <ul class="spec-list">
    {#each items as item (item.id)}
      <li>
        <button
          class="spec-item"
          class:spec-item-active={item.id === selectedId}
          type="button"
          disabled={isBusy}
          onclick={() => onSelect(item.id)}
        >
          <span class="spec-item-title">{item.title}</span>
          {#if item.meta}
            <span class="spec-item-meta">{item.meta}</span>
          {/if}
        </button>
      </li>
    {/each}
  </ul>
  {#if items.length === 0}
    <p class="spec-empty">{emptyMessage}</p>
  {/if}
</div>

<style>
  .spec-list-pane {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
  }

  .spec-pane-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--ui-space-2);
    margin-bottom: var(--ui-space-2);
  }

  .spec-pane-title {
    margin: 0;
    font-size: var(--ui-text-base);
  }

  .spec-list {
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-1);
    min-height: 0;
    margin: 0;
    padding: 0;
    list-style: none;
    overflow: auto;
  }

  .spec-item {
    width: 100%;
    min-height: var(--ui-control-height);
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 0.125rem;
    padding: 0.375rem 0.75rem;
    border: 1px solid transparent;
    border-radius: var(--ui-radius-md);
    background: transparent;
    color: inherit;
    text-align: left;
  }

  .spec-item-active {
    border-color: var(--ui-color-accent);
    background: color-mix(in srgb, var(--ui-color-accent) 12%, transparent);
  }

  .spec-item-meta {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }

  .spec-empty {
    margin: var(--ui-space-2) 0 0;
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }

  .spec-button {
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-surface);
    color: inherit;
  }

  .spec-item:disabled,
  .spec-button:disabled {
    cursor: default;
    opacity: 0.55;
  }
</style>
