<script lang="ts">
  import type { Snippet } from "svelte";
  import Icon from "../primitives/Icon.svelte";
  import type { OutlineRow } from "./outline";

  interface Props {
    rows: readonly OutlineRow[];
    rowSnippet?: Snippet<[OutlineRow]>;
    selectedId?: string;
    onSelect: (id: string) => void;
    collapsed: boolean;
    onCollapsedChange: (collapsed: boolean) => void;
  }

  let {
    rows,
    rowSnippet,
    selectedId,
    onSelect,
    collapsed,
    onCollapsedChange,
  }: Props = $props();
</script>

<nav class={["document-outline", { collapsed }]} aria-label="Document outline">
  <button
    type="button"
    class="document-outline-toggle"
    aria-label={collapsed
      ? "Expand document outline"
      : "Collapse document outline"}
    aria-expanded={!collapsed}
    onclick={() => onCollapsedChange(!collapsed)}
  >
    <Icon name={collapsed ? "chevron-right" : "chevron-down"} size={18} />
  </button>

  {#if !collapsed}
    <ul>
      {#each rows as row (row.id)}
        {#if row.type === "header"}
          {#if row.kind === "folder" && rowSnippet}
            <li class="document-outline-folder">
              {@render rowSnippet(row)}
            </li>
          {:else}
            <li class="document-outline-group">
              <span role="heading" aria-level="2">
                {#if row.icon}<Icon name={row.icon} size={16} />{/if}
                {row.label}
              </span>
              {#if rowSnippet}{@render rowSnippet(row)}{/if}
            </li>
          {/if}
        {:else}
          <li
            data-depth={row.depth}
            style:--depth={row.depth}
            draggable={row.dragData ? true : undefined}
            ondragstart={(event) => {
              if (row.dragData) {
                event.dataTransfer?.setData("text/plain", row.dragData);
                if (event.dataTransfer)
                  event.dataTransfer.effectAllowed = "move";
              }
            }}
          >
            <button
              type="button"
              aria-label={row.ariaLabel}
              aria-current={row.id === selectedId ? "page" : undefined}
              class={[
                "document-outline-row",
                { current: row.id === selectedId },
              ]}
              onclick={() => onSelect(row.id)}
            >
              <Icon name={row.icon} size={16} />
              <span class="document-outline-label">{row.label}</span>
            </button>
            {#if rowSnippet}{@render rowSnippet(row)}{/if}
          </li>
        {/if}
      {/each}
    </ul>
  {/if}
</nav>

<style>
  .document-outline {
    display: none;
  }

  @media (min-width: 75em) {
    .document-outline {
      min-width: 0;
      display: flex;
      flex-direction: column;
      gap: var(--ds-space-2);
      overflow: auto;
      padding: var(--ds-space-3) var(--ds-space-2);
      border-right: 1px solid var(--ds-color-border);
      background: var(--ds-color-border-soft);
    }

    .document-outline.collapsed {
      align-items: center;
      padding: var(--ds-space-2);
      overflow: hidden;
    }

    .document-outline-toggle {
      width: var(--ds-control-height);
      min-height: var(--ds-control-height);
      flex: none;
      border: 0;
      border-radius: var(--ds-radius-sm);
      background: transparent;
      color: var(--ds-color-text-secondary);
      display: grid;
      place-items: center;
    }

    .document-outline-toggle:hover {
      background: var(--ds-color-accent-soft);
      color: var(--ds-color-text);
    }

    .document-outline-toggle:focus-visible {
      outline: 2px solid var(--ds-color-focus);
      outline-offset: -2px;
    }

    ul {
      margin: 0;
      padding: 0;
      min-width: 0;
      list-style: none;
    }

    li {
      --indent-step: 0.875rem;
    }

    li[data-depth] {
      display: flex;
      align-items: center;
    }

    .document-outline-group {
      margin-top: var(--ds-space-3);
      padding: 0.375rem var(--ds-space-2);
      color: var(--ds-color-text-secondary);
      font-size: var(--ds-text-sm);
      font-weight: 600;
    }

    .document-outline-folder {
      margin-top: var(--ds-space-3);
    }

    :global(.document-outline-folder-header) {
      min-height: var(--ds-control-height);
      padding: 0.375rem var(--ds-space-2);
      border-radius: var(--ds-radius-sm);
      color: var(--ds-color-text-secondary);
      display: flex;
      align-items: center;
      gap: var(--ds-space-2);
      font-size: var(--ds-text-sm);
      font-weight: 600;
    }

    :global(.document-outline-folder-header.drop-target) {
      background: var(--ds-color-accent-soft);
      color: var(--ds-color-text);
    }

    :global(.document-outline-folder-delete),
    :global(.document-outline-move) {
      width: 1.75rem;
      height: 1.75rem;
      flex: none;
      padding: 0;
      border: 0;
      border-radius: var(--ds-radius-sm);
      background: transparent;
      color: var(--ds-color-text-faint);
      display: grid;
      place-items: center;
    }

    :global(.document-outline-folder-delete) {
      margin-left: auto;
    }

    :global(.document-outline-folder-delete:hover),
    :global(.document-outline-move:hover) {
      background: var(--ds-color-accent-soft);
      color: var(--ds-color-text);
    }

    :global(.document-outline-move-menu) {
      z-index: 100;
      min-width: 10rem;
      padding: 0.25rem;
      border: 1px solid var(--ds-color-border);
      border-radius: var(--ds-radius-md);
      background: var(--ds-color-paper);
      box-shadow: var(--ds-shadow-md);
    }

    :global(.document-outline-move-menu [role="menuitem"]) {
      min-height: var(--ds-control-height);
      padding: 0.25rem 0.5rem;
      border-radius: var(--ds-radius-sm);
      outline: 0;
    }

    :global(.document-outline-move-menu [role="menuitem"][data-highlighted]) {
      background: var(--ds-color-accent-soft);
    }

    .document-outline-row {
      width: 100%;
      flex: 1;
      min-height: var(--ds-control-height);
      padding: 0.375rem var(--ds-space-2);
      padding-inline-start: calc(
        var(--ds-space-2) + var(--depth, 0) * var(--indent-step)
      );
      border: 0;
      border-radius: var(--ds-radius-sm);
      background: transparent;
      color: var(--ds-color-text-secondary);
      display: flex;
      align-items: center;
      gap: var(--ds-space-2);
      text-align: left;
    }

    .document-outline-row:hover,
    .document-outline-row.current {
      background: var(--ds-color-accent-soft);
      color: var(--ds-color-text);
    }

    .document-outline-row.current {
      font-weight: 600;
    }

    .document-outline-row:focus-visible {
      outline: 2px solid var(--ds-color-focus);
      outline-offset: -2px;
    }

    .document-outline-label {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }
</style>
