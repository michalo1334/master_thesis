<script lang="ts">
  import type { Node } from "../../../contracts.generated/graph";
  import {
    topologyEntityLabel,
    unplacedSelection,
    type TopologyEntitySelection,
    type TopologyScene,
    type TopologyUnplacedEntry,
  } from "../topology-scene";
  import { unplacedReason, unplacedReasonCode } from "../topology-placement";

  interface Props {
    scene: TopologyScene;
    /** Selects the entity, focuses it, and opens its inspector. */
    onSelect: (selection: TopologyEntitySelection) => void;
    onClose?: () => void;
  }

  let { scene, onSelect, onClose = undefined }: Props = $props();

  /** Names the scene knows, so an issue can name its related entities. */
  let nodeById = $derived.by(() => {
    const map = new Map<string, Node>();
    for (const segment of scene.segments) {
      map.set(segment.id, segment.node);
      for (const host of segment.hosts) {
        map.set(host.id, host.node);
        for (const service of host.services) map.set(service.id, service.node);
      }
    }
    for (const attachment of scene.attachments) {
      map.set(attachment.id, attachment.node);
    }
    for (const entry of scene.unplaced) {
      if (entry.node) map.set(entry.entityId, entry.node);
    }
    return map;
  });

  function label(entry: TopologyUnplacedEntry): string {
    if (entry.node) return topologyEntityLabel(entry.node);
    if (entry.edge) return `${entry.edge.type} relationship`;
    return entry.entityId;
  }

  /**
   * Entities the reason relates to, by visible name.
   *
   * A projector issue names related graph entities. A broken reference names
   * the projection records that carry it. The row already shows the missing
   * entity, so an owner that is the missing entity itself adds nothing.
   */
  function relatedLabels(entry: TopologyUnplacedEntry): string[] {
    const ids = entry.issue
      ? entry.issue.related_ids
      : (entry.missing?.ownerIds ?? []);
    return ids
      .filter((id) => id !== entry.entityId)
      .map((id) => {
        const node = nodeById.get(id);
        return node ? topologyEntityLabel(node) : id;
      });
  }

  function isPending(entry: TopologyUnplacedEntry): boolean {
    return entry.status === "pending";
  }
</script>

{#snippet entryContent(entry: TopologyUnplacedEntry)}
  <span class="topology-unplaced-name">{label(entry)}</span>
  <span class="topology-unplaced-reason">{unplacedReason(entry)}</span>
  {#if relatedLabels(entry).length > 0}
    <span class="topology-unplaced-related"
      >Related: {relatedLabels(entry).join(", ")}</span
    >
  {/if}
{/snippet}

<section
  class="topology-unplaced-tray"
  aria-label="Unplaced entities"
  data-unplaced-count={scene.unplaced.length}
>
  <header class="topology-unplaced-header">
    <h2 class="topology-unplaced-title">
      <span aria-hidden="true">&#9888;</span>
      Unplaced · {scene.unplaced.length}
    </h2>
    {#if onClose}
      <button
        type="button"
        class="topology-unplaced-close"
        aria-label="Close unplaced tray"
        onclick={onClose}>Close</button
      >
    {/if}
  </header>
  <ul class="topology-unplaced-list">
    {#each scene.unplaced as entry (entry.key)}
      {@const selection = unplacedSelection(entry)}
      <li>
        {#if selection}
          <button
            type="button"
            class="topology-unplaced-item"
            class:is-pending={isPending(entry)}
            data-unplaced-entity={entry.entityId}
            data-unplaced-status={entry.status}
            data-unplaced-reason={unplacedReasonCode(entry)}
            data-unplaced-selectable="true"
            aria-label={`${label(entry)}, ${unplacedReason(entry)}`}
            onclick={() => onSelect(selection)}
          >
            {@render entryContent(entry)}
          </button>
        {:else}
          <!--
            The reason names an entity the graph does not contain, so there is
            nothing to select. The row stays readable and inert.
          -->
          <div
            class="topology-unplaced-item is-unselectable"
            class:is-pending={isPending(entry)}
            data-unplaced-entity={entry.entityId}
            data-unplaced-status={entry.status}
            data-unplaced-reason={unplacedReasonCode(entry)}
            data-unplaced-selectable="false"
          >
            {@render entryContent(entry)}
          </div>
        {/if}
      </li>
    {/each}
  </ul>
</section>

<style>
  .topology-unplaced-tray {
    display: flex;
    flex-direction: column;
    overflow: auto;
    padding: var(--ui-space-2);
    border: 1px solid var(--ui-color-warning);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
  }
  .topology-unplaced-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--ui-space-2);
  }
  .topology-unplaced-title {
    margin: 0;
    color: var(--ui-color-warning-text);
    font-size: var(--ui-text-sm);
    font-weight: 700;
  }
  .topology-unplaced-close {
    min-height: var(--ui-control-height);
    padding: 0 var(--ui-space-1);
    border: 0;
    background: transparent;
    color: var(--ui-color-text-secondary);
    font: inherit;
    font-size: var(--ui-text-xs);
  }
  .topology-unplaced-list {
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-1);
    margin: var(--ui-space-1) 0 0;
    padding: 0;
    list-style: none;
  }
  .topology-unplaced-item {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    width: 100%;
    min-height: var(--ui-control-height);
    padding: var(--ui-space-1) var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-surface);
    color: var(--ui-color-text);
    font: inherit;
    font-size: var(--ui-text-sm);
    text-align: left;
  }
  .topology-unplaced-item:hover:not(.is-unselectable) {
    background: var(--ui-color-accent-soft);
  }
  /* An entity the graph does not contain cannot be selected or dragged. */
  .topology-unplaced-item.is-unselectable {
    border-style: dotted;
    color: var(--ui-color-text-secondary);
  }
  /* Pending entities wait for a projection. Placement issues need an edit. */
  .topology-unplaced-item.is-pending {
    border-style: dashed;
    border-color: var(--ui-color-warning);
  }
  .topology-unplaced-item:not(.is-pending):not(.is-unselectable) {
    border-color: var(--ui-color-danger);
  }
  .topology-unplaced-reason {
    color: var(--ui-color-warning-text);
    font: var(--ui-text-xs) var(--ui-font-mono);
  }
  .topology-unplaced-related {
    color: var(--ui-color-text-muted);
    font: var(--ui-text-xs) var(--ui-font-mono);
  }
</style>
