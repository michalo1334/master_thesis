<script lang="ts">
  import { DropdownMenu } from "bits-ui";
  import { Icon } from "../../ui-kit/primitives";
  import type { FolderSummary } from "../contract";
  import {
    buildRows,
    graphIdForDocument,
    rowKey,
    type OutlineRow,
  } from "./document-outline";
  import type { WorkspaceDocument } from "./WorkspaceDocument.svelte";

  interface Props {
    documents: readonly WorkspaceDocument[];
    folders?: readonly FolderSummary[];
    graphSummaries?: readonly import("../contract").GraphSummary[];
    selectedDocumentId?: string;
    onSelectDocument: (id: string) => void;
    onDeleteFolder?: (folderId: string) => Promise<boolean> | boolean;
    onMoveGraph?: (
      graphId: string,
      folderId: string | null,
    ) => Promise<boolean> | boolean;
    collapsed: boolean;
    onCollapsedChange: (collapsed: boolean) => void;
  }

  let {
    documents,
    folders = [],
    graphSummaries = [],
    selectedDocumentId,
    onSelectDocument,
    onDeleteFolder = () => false,
    onMoveGraph = () => false,
    collapsed,
    onCollapsedChange,
  }: Props = $props();

  let rows: OutlineRow[] = $derived(
    buildRows(documents, folders, graphSummaries),
  );
  let dragFolderId = $state<string>();

  function startDrag(event: DragEvent, graphId: string): void {
    event.dataTransfer?.setData("text/plain", graphId);
    if (event.dataTransfer) event.dataTransfer.effectAllowed = "move";
  }

  function allowFolderDrop(event: DragEvent, folderId: string): void {
    event.preventDefault();
    dragFolderId = folderId;
    if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
  }

  function moveDroppedGraph(event: DragEvent, folderId: string): void {
    event.preventDefault();
    dragFolderId = undefined;
    const graphId = event.dataTransfer?.getData("text/plain");
    if (graphId) void onMoveGraph(graphId, folderId);
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
      {#each rows as row (rowKey(row))}
        {#if row.type === "folder"}
          <li class="document-outline-folder">
            <div
              class={[
                "document-outline-folder-header",
                { "drop-target": dragFolderId === row.folder.id },
              ]}
              role="heading"
              aria-level="2"
              ondragover={(event) => allowFolderDrop(event, row.folder.id)}
              ondragleave={() => (dragFolderId = undefined)}
              ondrop={(event) => moveDroppedGraph(event, row.folder.id)}
            >
              <Icon name="folder" size={16} />
              <span>{row.folder.name}</span>
              <button
                type="button"
                class="document-outline-folder-delete"
                aria-label={`Delete ${row.folder.name}`}
                onclick={(event) => {
                  event.stopPropagation();
                  void onDeleteFolder(row.folder.id);
                }}
              >
                <Icon name="trash" size={15} />
              </button>
            </div>
          </li>
        {:else if row.type === "reports"}
          <li class="document-outline-group">
            <span role="heading" aria-level="2">Reports</span>
          </li>
        {:else if row.type === "analyses"}
          <li class="document-outline-group">
            <span role="heading" aria-level="2">Analyses</span>
          </li>
        {:else if row.type === "analysis"}
          <li class="document-outline-analysis">
            <span role="heading" aria-level="3">{row.title}</span>
          </li>
        {:else}
          {@const documentGraphId = graphIdForDocument(row.document)}
          <li
            data-depth={row.depth}
            style:--depth={row.depth}
            draggable={documentGraphId ? true : undefined}
            ondragstart={(event) =>
              documentGraphId && startDrag(event, documentGraphId)}
          >
            <button
              type="button"
              aria-label={`${row.document.documentLabel} ${row.document.title}`}
              aria-current={row.document.id === selectedDocumentId
                ? "page"
                : undefined}
              class={[
                "document-outline-row",
                { current: row.document.id === selectedDocumentId },
              ]}
              onclick={() => onSelectDocument(row.document.id)}
            >
              <Icon name={row.document.icon} size={16} />
              <span class="document-outline-label">{row.document.title}</span>
            </button>
            {#if documentGraphId}
              <DropdownMenu.Root>
                <DropdownMenu.Trigger
                  class="document-outline-move"
                  aria-label={`Move ${row.document.title}`}
                  title="Move graph"
                >
                  <Icon name="folder" size={15} />
                </DropdownMenu.Trigger>
                <DropdownMenu.Portal>
                  <DropdownMenu.Content class="document-outline-move-menu">
                    <DropdownMenu.Item
                      onclick={() => void onMoveGraph(documentGraphId, null)}
                    >
                      Move to root
                    </DropdownMenu.Item>
                    {#each folders as folder (folder.id)}
                      <DropdownMenu.Item
                        onclick={() =>
                          void onMoveGraph(documentGraphId, folder.id)}
                      >
                        {folder.name}
                      </DropdownMenu.Item>
                    {/each}
                  </DropdownMenu.Content>
                </DropdownMenu.Portal>
              </DropdownMenu.Root>
            {/if}
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
    .document-outline-analysis {
      padding: 0.25rem var(--ds-space-2);
      color: var(--ds-color-text-secondary);
      font-size: var(--ds-text-xs);
      font-weight: 600;
    }

    .document-outline-folder {
      margin-top: var(--ds-space-3);
    }

    .document-outline-folder-header {
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

    .document-outline-folder-header.drop-target {
      background: var(--ds-color-accent-soft);
      color: var(--ds-color-text);
    }

    .document-outline-folder-delete,
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

    .document-outline-folder-delete {
      margin-left: auto;
    }

    .document-outline-folder-delete:hover,
    :global(.document-outline-move:hover) {
      background: var(--ds-color-accent-soft);
      color: var(--ds-color-text);
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
  }
</style>
