<script lang="ts" generics="DragData = unknown, DropData = unknown">
  import type { Snippet } from "svelte";
  import Icon from "../primitives/Icon.svelte";
  import type { OutlineDrag, OutlineRow } from "./outline";

  interface Props {
    rows: readonly OutlineRow<DragData, DropData>[];
    rowSnippet?: Snippet<[OutlineRow<DragData, DropData>]>;
    selectedId?: string;
    onSelect: (id: string, event: MouseEvent) => void;
    collapsed: boolean;
    onCollapsedChange: (collapsed: boolean) => void;
    onDrop?: (drag: DragData, drop: DropData) => void;
    canDrop?: (drag: DragData, drop: DropData) => boolean;
  }

  let {
    rows,
    rowSnippet,
    selectedId,
    onSelect,
    collapsed,
    onCollapsedChange,
    onDrop,
    canDrop,
  }: Props = $props();

  let activeDrag = $state<OutlineDrag<DragData> | undefined>();
  let dropTargetId = $state<string>();

  function acceptsDrop(row: OutlineRow<DragData, DropData>): boolean {
    if (row.type !== "header" || !row.drop || activeDrag === undefined)
      return false;
    return canDrop?.(activeDrag.data, row.drop.data) !== false;
  }
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
        {@const drag = row.type === "item" ? row.drag : undefined}
        {@const dropData =
          row.type === "header" && row.drop ? row.drop.data : undefined}
        {@const isDropTarget = acceptsDrop(row)}
        <li
          class={[
            row.type === "header" && row.kind === "folder" && rowSnippet
              ? "document-outline-folder"
              : row.type === "header" && row.level === 3
                ? "document-outline-section"
                : row.type === "header"
                  ? "document-outline-group"
                  : undefined,
            { "drop-target": dropTargetId === row.id },
          ]}
          data-depth={row.type === "item" ? row.depth : undefined}
          style:--depth={row.type === "item" ? row.depth : undefined}
          draggable={drag ? true : undefined}
          ondragstart={(event) => {
            if (drag) {
              event.dataTransfer?.setData("text/plain", row.id);
              if (event.dataTransfer) event.dataTransfer.effectAllowed = "move";
              activeDrag = drag;
            }
          }}
          ondragend={() => {
            activeDrag = undefined;
            dropTargetId = undefined;
          }}
          ondragover={(event) => {
            if (isDropTarget) {
              event.preventDefault();
              if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
              dropTargetId = row.id;
            }
          }}
          ondragleave={(event) => {
            if (
              dropTargetId === row.id &&
              !event.currentTarget.contains(event.relatedTarget as Node)
            ) {
              dropTargetId = undefined;
            }
          }}
          ondrop={(event) => {
            if (isDropTarget) {
              event.preventDefault();
              onDrop?.(activeDrag!.data, dropData!);
              activeDrag = undefined;
              dropTargetId = undefined;
            }
          }}
        >
          {#if row.type === "header"}
            {#if row.kind === "folder" && rowSnippet}
              {@render rowSnippet(row)}
            {:else}
              <span role="heading" aria-level={row.level}>
                {#if row.icon}<Icon name={row.icon} size={16} />{/if}
                {row.label}
              </span>
              {#if rowSnippet}{@render rowSnippet(row)}{/if}
            {/if}
          {:else}
            <button
              type="button"
              aria-label={row.ariaLabel}
              aria-current={row.id === selectedId ? "page" : undefined}
              aria-pressed={row.pressed}
              class={[
                "document-outline-row",
                { current: row.id === selectedId },
              ]}
              onclick={(event) => onSelect(row.id, event)}
            >
              <Icon name={row.pressed ? "check" : row.icon} size={16} />
              <span class="document-outline-label">{row.label}</span>
            </button>
            {#if rowSnippet}{@render rowSnippet(row)}{/if}
          {/if}
        </li>
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
      gap: var(--ui-space-2);
      overflow: auto;
      padding: var(--ui-space-3) var(--ui-space-2);
      border-right: 1px solid var(--ui-color-border);
      background: var(--ui-color-border-soft);
    }

    .document-outline.collapsed {
      align-items: center;
      padding: var(--ui-space-2);
      overflow: hidden;
    }

    .document-outline-toggle {
      width: var(--ui-control-height);
      min-height: var(--ui-control-height);
      flex: none;
      border: 0;
      border-radius: var(--ui-radius-sm);
      background: transparent;
      color: var(--ui-color-text-secondary);
      display: grid;
      place-items: center;
    }

    .document-outline-toggle:hover {
      background: var(--ui-color-accent-soft);
      color: var(--ui-color-text);
    }

    .document-outline-toggle:focus-visible {
      outline: 2px solid var(--ui-color-focus);
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

    li.drop-target {
      border-radius: var(--ui-radius-sm);
      background: var(--ui-color-accent-soft);
    }

    :global(li.drop-target .document-outline-folder-header) {
      background: var(--ui-color-accent-soft);
      color: var(--ui-color-text);
    }

    .document-outline-group {
      margin-top: var(--ui-space-3);
      padding: 0.375rem var(--ui-space-2);
      color: var(--ui-color-text-secondary);
      font-size: var(--ui-text-sm);
      font-weight: 600;
    }

    .document-outline-section {
      padding: 0.25rem var(--ui-space-2);
      color: var(--ui-color-text-secondary);
      font-size: var(--ui-text-xs);
      font-weight: 600;
    }

    .document-outline-folder {
      margin-top: var(--ui-space-3);
    }

    :global(.document-outline-folder-header) {
      min-height: var(--ui-control-height);
      padding: 0.375rem var(--ui-space-2);
      border-radius: var(--ui-radius-sm);
      color: var(--ui-color-text-secondary);
      display: flex;
      align-items: center;
      gap: var(--ui-space-2);
      font-size: var(--ui-text-sm);
      font-weight: 600;
    }

    :global(.document-outline-folder-delete),
    :global(.document-outline-move) {
      width: 1.75rem;
      height: 1.75rem;
      flex: none;
      padding: 0;
      border: 0;
      border-radius: var(--ui-radius-sm);
      background: transparent;
      color: var(--ui-color-text-faint);
      display: grid;
      place-items: center;
    }

    :global(.document-outline-folder-delete) {
      margin-left: auto;
    }

    :global(.document-outline-folder-delete:hover),
    :global(.document-outline-move:hover) {
      background: var(--ui-color-accent-soft);
      color: var(--ui-color-text);
    }

    :global(.document-outline-move-menu) {
      z-index: 100;
      min-width: 10rem;
      padding: 0.25rem;
      border: 1px solid var(--ui-color-border);
      border-radius: var(--ui-radius-md);
      background: var(--ui-color-paper);
      box-shadow: var(--ui-shadow-md);
    }

    :global(.document-outline-move-menu [role="menuitem"]) {
      min-height: var(--ui-control-height);
      padding: 0.25rem 0.5rem;
      border-radius: var(--ui-radius-sm);
      outline: 0;
    }

    :global(.document-outline-move-menu [role="menuitem"][data-highlighted]) {
      background: var(--ui-color-accent-soft);
    }

    .document-outline-row {
      width: 100%;
      flex: 1;
      min-height: var(--ui-control-height);
      padding: 0.375rem var(--ui-space-2);
      padding-inline-start: calc(
        var(--ui-space-2) + var(--depth, 0) * var(--indent-step)
      );
      border: 0;
      border-radius: var(--ui-radius-sm);
      background: transparent;
      color: var(--ui-color-text-secondary);
      display: flex;
      align-items: center;
      gap: var(--ui-space-2);
      text-align: left;
    }

    .document-outline-row:hover,
    .document-outline-row.current {
      background: var(--ui-color-accent-soft);
      color: var(--ui-color-text);
    }

    .document-outline-row.current {
      font-weight: 600;
    }

    .document-outline-row:focus-visible {
      outline: 2px solid var(--ui-color-focus);
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
