<script lang="ts">
  import {
    topologyEntityLabel,
    unplacedSelection,
    type TopologyEntitySelection,
    type TopologyScene,
    type TopologyUnplacedEntry,
  } from "../topology-scene";
  import { unplacedReason } from "../topology-placement";

  interface Props {
    scene: TopologyScene;
    /** Entity the canvas currently selects. */
    selectedEntityId?: string;
    /** Activates the same lens as canvas focus and opens the inspector. */
    onSelect: (selection: TopologyEntitySelection) => void;
  }

  let { scene, selectedEntityId = undefined, onSelect }: Props = $props();

  function activate(nodeId: string): void {
    onSelect({ kind: "node", id: nodeId });
  }

  /** Visible name of an Unplaced entry, which can lack a graph node. */
  function unplacedLabel(entry: TopologyUnplacedEntry): string {
    if (entry.node) return topologyEntityLabel(entry.node);
    if (entry.edge) return `${entry.edge.type} relationship`;
    return entry.entityId;
  }

  function unplacedName(entry: TopologyUnplacedEntry): string {
    return `${unplacedLabel(entry)}, ${unplacedReason(entry)}`;
  }

  function isSelected(entityId: string): boolean {
    return entityId === selectedEntityId;
  }
</script>

{#snippet unplacedContent(entry: TopologyUnplacedEntry)}
  <span class="topology-navigator-name">{unplacedLabel(entry)}</span>
  <span class="topology-navigator-reason">{unplacedReason(entry)}</span>
{/snippet}

<nav class="topology-navigator" aria-label="Topology navigator">
  <ul class="topology-navigator-tree">
    {#each scene.segments as segment (segment.id)}
      <li>
        <button
          type="button"
          class="topology-navigator-item"
          data-navigator-kind="segment"
          data-navigator-entity={segment.id}
          class:is-selected={isSelected(segment.id)}
          aria-current={isSelected(segment.id) ? "true" : undefined}
          aria-label={`Segment ${segment.node.data.name}`}
          onclick={() => activate(segment.id)}
        >
          {segment.node.data.name}
        </button>
        {#if segment.hosts.length > 0}
          <ul class="topology-navigator-tree">
            {#each segment.hosts as host (host.id)}
              <li>
                <button
                  type="button"
                  class="topology-navigator-item"
                  data-navigator-kind="host"
                  data-navigator-entity={host.id}
                  class:is-selected={isSelected(host.id)}
                  aria-current={isSelected(host.id) ? "true" : undefined}
                  aria-label={`Host ${host.node.data.name}`}
                  onclick={() => activate(host.id)}
                >
                  {host.node.data.name}
                </button>
                {#if host.services.length > 0}
                  <ul class="topology-navigator-tree">
                    {#each host.services as service (service.id)}
                      <li>
                        <button
                          type="button"
                          class="topology-navigator-item"
                          data-navigator-kind="service"
                          data-navigator-entity={service.id}
                          class:is-selected={isSelected(service.id)}
                          aria-current={isSelected(service.id)
                            ? "true"
                            : undefined}
                          aria-label={`Service ${service.node.data.name}`}
                          onclick={() => activate(service.id)}
                        >
                          {service.node.data.name}
                        </button>
                      </li>
                    {/each}
                  </ul>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
      </li>
    {/each}
  </ul>

  {#if scene.attachments.length > 0}
    <p class="topology-navigator-section">Attached context</p>
    <ul class="topology-navigator-tree">
      {#each scene.attachments as attachment (attachment.id)}
        <li>
          <button
            type="button"
            class="topology-navigator-item"
            data-navigator-kind="context"
            data-navigator-entity={attachment.id}
            class:is-selected={isSelected(attachment.id)}
            aria-current={isSelected(attachment.id) ? "true" : undefined}
            aria-label={`${attachment.node.type} ${topologyEntityLabel(
              attachment.node,
            )}`}
            onclick={() => activate(attachment.id)}
          >
            {topologyEntityLabel(attachment.node)}
          </button>
        </li>
      {/each}
    </ul>
  {/if}

  {#if scene.unplaced.length > 0}
    <p class="topology-navigator-section">Unplaced</p>
    <ul class="topology-navigator-tree">
      {#each scene.unplaced as entry (entry.key)}
        {@const selection = unplacedSelection(entry)}
        <li>
          {#if selection}
            <button
              type="button"
              class="topology-navigator-item is-unplaced"
              data-navigator-kind="unplaced"
              data-navigator-entity={entry.entityId}
              data-unplaced-status={entry.status}
              data-navigator-selectable="true"
              class:is-selected={isSelected(entry.entityId)}
              aria-current={isSelected(entry.entityId) ? "true" : undefined}
              aria-label={unplacedName(entry)}
              onclick={() => onSelect(selection)}
            >
              {@render unplacedContent(entry)}
            </button>
          {:else}
            <!--
              A broken reference can name an entity the graph does not contain.
              The row reports the reason and stays inert, so activation cannot
              create a dangling selection.
            -->
            <div
              class="topology-navigator-item is-unplaced is-unselectable"
              data-navigator-kind="unplaced"
              data-navigator-entity={entry.entityId}
              data-unplaced-status={entry.status}
              data-navigator-selectable="false"
            >
              {@render unplacedContent(entry)}
            </div>
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
</nav>

<style>
  .topology-navigator {
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-1);
    overflow: auto;
    padding: var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
  }
  .topology-navigator-tree {
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .topology-navigator-tree .topology-navigator-tree {
    padding-left: var(--ui-space-3);
  }
  .topology-navigator-section {
    margin: var(--ui-space-2) 0 0;
    color: var(--ui-color-text-muted);
    font-size: var(--ui-text-xs);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }
  .topology-navigator-item {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    width: 100%;
    min-height: var(--ui-control-height);
    padding: var(--ui-space-1) var(--ui-space-2);
    border: 0;
    border-radius: var(--ui-radius-sm);
    background: transparent;
    color: var(--ui-color-text);
    font: inherit;
    font-size: var(--ui-text-sm);
    text-align: left;
  }
  .topology-navigator-item:hover:not(.is-unselectable) {
    background: var(--ui-color-accent-soft);
  }
  .topology-navigator-item.is-selected {
    background: var(--ui-color-accent-soft);
    font-weight: 700;
  }
  .topology-navigator-item.is-unselectable {
    color: var(--ui-color-text-secondary);
  }
  .topology-navigator-reason {
    color: var(--ui-color-warning-text);
    font: var(--ui-text-xs) var(--ui-font-mono);
  }
</style>
