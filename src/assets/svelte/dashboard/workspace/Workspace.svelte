<script lang="ts">
  import { Dialog, DropdownMenu, Tabs } from "bits-ui";
  import type { Snippet } from "svelte";
  import { Icon } from "../../ui-kit/primitives";
  import { DocumentOutline, type OutlineRow } from "../../ui-kit/workspace";
  import { buildDashboardRows } from "./build-dashboard-rows";
  import type { WorkspaceDocument } from "./WorkspaceModel.svelte";
  import type { WorkspaceModel } from "./WorkspaceModel.svelte";

  export type { WorkspaceDocument };

  export type WorkspaceOrientation = "horizontal" | "vertical";

  interface Props {
    model: WorkspaceModel;
    orientation?: WorkspaceOrientation;
    content?: Snippet<[WorkspaceDocument]>;
    onCreateFolder: (name: string) => Promise<boolean> | boolean;
    onDeleteFolder: (folderId: string) => Promise<boolean> | boolean;
    onMoveGraph: (
      graphId: string,
      folderId: string | null,
    ) => Promise<boolean> | boolean;
  }

  let {
    model,
    orientation = "horizontal",
    content = undefined,
    onCreateFolder,
    onDeleteFolder,
    onMoveGraph,
  }: Props = $props();

  let outlineRows: readonly OutlineRow[] = $derived(
    buildDashboardRows(model.documents, model.folders, model.graphSummaries),
  );
  let dragFolderId = $state<string>();

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

  let activeDocument = $derived(
    model.documents.find(
      (document) => document.id === model.selectedDocumentId,
    ),
  );
  let outlineCollapsed = $state(false);
  let folderDialogOpen = $state(false);
  let folderName = $state("");
  let isCreatingFolder = $state(false);
  let draggedDocumentId = $state<string>();
  let dropTargetId = $state<string>();

  function closeDocument(event: MouseEvent, id: string) {
    event.stopPropagation();
    model.closeDocument(id);
  }

  async function createFolder(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (isCreatingFolder) return;

    isCreatingFolder = true;
    try {
      if (await onCreateFolder(folderName)) {
        folderName = "";
        folderDialogOpen = false;
      }
    } finally {
      isCreatingFolder = false;
    }
  }

  function startDocumentDrag(event: DragEvent, documentId: string): void {
    draggedDocumentId = documentId;
    event.dataTransfer?.setData("text/plain", documentId);
    if (event.dataTransfer) event.dataTransfer.effectAllowed = "move";
  }

  function allowDocumentDrop(event: DragEvent, targetId: string): void {
    if (!draggedDocumentId || draggedDocumentId === targetId) return;
    event.preventDefault();
    dropTargetId = targetId;
    if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
  }

  function dropDocument(event: DragEvent, targetId: string): void {
    event.preventDefault();
    const draggedId =
      event.dataTransfer?.getData("text/plain") || draggedDocumentId;
    if (draggedId) model.reorderDocuments(draggedId, targetId);
    draggedDocumentId = undefined;
    dropTargetId = undefined;
  }

  function reorderDocumentWithKeyboard(
    event: KeyboardEvent,
    documentId: string,
  ): void {
    if (!event.altKey || !["ArrowLeft", "ArrowRight"].includes(event.key)) {
      return;
    }
    const index = model.documents.findIndex(
      (document) => document.id === documentId,
    );
    const target =
      model.documents[index + (event.key === "ArrowLeft" ? -1 : 1)];
    if (!target) return;
    event.preventDefault();
    model.reorderDocuments(documentId, target.id);
  }
</script>

<main
  class={[
    "dashboard-workspace",
    { "dashboard-workspace-outline-collapsed": outlineCollapsed },
  ]}
>
  <DocumentOutline
    rows={outlineRows}
    selectedId={model.selectedDocumentId}
    onSelect={(id) => model.selectDocument(id)}
    collapsed={outlineCollapsed}
    onCollapsedChange={(collapsed) => (outlineCollapsed = collapsed)}
  >
    {#snippet rowSnippet(row)}
      {#if row.type === "header" && row.kind === "folder"}
        <div
          class={[
            "document-outline-folder-header",
            { "drop-target": dragFolderId === row.id.replace("group:", "") },
          ]}
          role="heading"
          aria-level="2"
          ondragover={(event) => {
            const fid = row.id.replace("group:", "");
            allowFolderDrop(event, fid);
          }}
          ondragleave={() => (dragFolderId = undefined)}
          ondrop={(event) => {
            const fid = row.id.replace("group:", "");
            moveDroppedGraph(event, fid);
          }}
        >
          <span>{row.label}</span>
          <button
            type="button"
            class="document-outline-folder-delete"
            aria-label={`Delete ${row.label}`}
            onclick={(event) => {
              event.stopPropagation();
              void onDeleteFolder(row.id.replace("group:", ""));
            }}
          >
            <Icon name="trash" size={15} />
          </button>
        </div>
      {:else if row.type === "item" && row.dragData}
        <DropdownMenu.Root>
          <DropdownMenu.Trigger
            class="document-outline-move"
            aria-label={`Move ${row.label}`}
            title="Move graph"
          >
            <Icon name="folder" size={15} />
          </DropdownMenu.Trigger>
          <DropdownMenu.Portal>
            <DropdownMenu.Content class="document-outline-move-menu">
              <DropdownMenu.Item
                onclick={() => void onMoveGraph(row.dragData!, null)}
              >
                Move to root
              </DropdownMenu.Item>
              {#each model.folders as folder (folder.id)}
                <DropdownMenu.Item
                  onclick={() => void onMoveGraph(row.dragData!, folder.id)}
                >
                  {folder.name}
                </DropdownMenu.Item>
              {/each}
            </DropdownMenu.Content>
          </DropdownMenu.Portal>
        </DropdownMenu.Root>
      {/if}
    {/snippet}
  </DocumentOutline>

  <Tabs.Root
    class="dashboard-document"
    {orientation}
    value={model.selectedDocumentId}
    onValueChange={(id) => model.selectDocument(id)}
    loop
  >
    <div class="dashboard-document-tabs-container">
      <Tabs.List class="dashboard-document-tabs" aria-label="Open documents">
        {#each model.documents as document (document.id)}
          <div
            class={[
              "dashboard-document-item",
              { "drop-target": dropTargetId === document.id },
            ]}
            role="group"
            aria-label={`Document tab ${document.title}`}
            draggable="true"
            ondragstart={(event) => startDocumentDrag(event, document.id)}
            ondragover={(event) => allowDocumentDrop(event, document.id)}
            ondragleave={(event) => {
              if (!event.currentTarget.contains(event.relatedTarget as Node)) {
                dropTargetId = undefined;
              }
            }}
            ondragend={() => {
              draggedDocumentId = undefined;
              dropTargetId = undefined;
            }}
            ondrop={(event) => dropDocument(event, document.id)}
          >
            <Tabs.Trigger
              class="dashboard-document-tab"
              value={document.id}
              onkeydown={(event) =>
                reorderDocumentWithKeyboard(event, document.id)}
            >
              <span class="dashboard-document-dot" aria-hidden="true"></span>
              <span class="dashboard-document-title">{document.title}</span>
            </Tabs.Trigger>
            <button
              type="button"
              class="dashboard-document-close"
              aria-label={`Close ${document.title}`}
              disabled={!model.canCloseDocument(document)}
              onclick={(event) => closeDocument(event, document.id)}
              >&times;</button
            >
          </div>
        {/each}
      </Tabs.List>

      <DropdownMenu.Root>
        <DropdownMenu.Trigger
          class="dashboard-document-add"
          aria-label="Create document"
        >
          <Icon name="plus" size={18} />
        </DropdownMenu.Trigger>
        <DropdownMenu.Portal>
          <DropdownMenu.Content
            class="dashboard-document-create-menu"
            side="bottom"
            sideOffset={4}
            align="start"
          >
            {#each model.documentTypes as documentType (documentType.id)}
              <DropdownMenu.Item
                onclick={() => model.handleCreateDocument(documentType.id)}
              >
                {#if documentType.icon}
                  <Icon name={documentType.icon} size={16} />
                {/if}
                <span>{documentType.label}</span>
              </DropdownMenu.Item>
            {/each}
            <DropdownMenu.Item onclick={() => (folderDialogOpen = true)}>
              <Icon name="folder" size={16} />
              <span>Folder</span>
            </DropdownMenu.Item>
          </DropdownMenu.Content>
        </DropdownMenu.Portal>
      </DropdownMenu.Root>
    </div>

    {#if activeDocument}
      <Tabs.Content class="dashboard-document-panel" value={activeDocument.id}>
        {@render content?.(activeDocument)}
      </Tabs.Content>
    {/if}

    {#if model.documents.length === 0}
      <section class="dashboard-workspace-empty" aria-label="No open documents">
        <p>No documents opened</p>
      </section>
    {/if}
  </Tabs.Root>
</main>

<Dialog.Root bind:open={folderDialogOpen}>
  {#if folderDialogOpen}
    <Dialog.Portal>
      <Dialog.Overlay class="folder-dialog-overlay" />
      <Dialog.Content class="folder-dialog">
        <Dialog.Title>New folder</Dialog.Title>
        <Dialog.Description
          >Group saved graphs in the document outline.</Dialog.Description
        >
        <form onsubmit={createFolder}>
          <label for="folder-name">Name</label>
          <input id="folder-name" bind:value={folderName} maxlength="100" />
          {#if model.statusMessage}
            <p class="folder-dialog-status" role="alert">
              {model.statusMessage}
            </p>
          {/if}
          <div class="folder-dialog-actions">
            <Dialog.Close type="button" disabled={isCreatingFolder}
              >Cancel</Dialog.Close
            >
            <button type="submit" disabled={isCreatingFolder}>Create</button>
          </div>
        </form>
      </Dialog.Content>
    </Dialog.Portal>
  {/if}
</Dialog.Root>

<style>
  :global(.folder-dialog-overlay) {
    position: fixed;
    z-index: 200;
    inset: 0;
    background: color-mix(in srgb, var(--ui-color-nav) 45%, transparent);
  }
  :global(.folder-dialog) {
    position: fixed;
    z-index: 201;
    top: 50%;
    left: 50%;
    width: min(26rem, calc(100vw - 2rem));
    padding: 1.5rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-lg);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
    color: var(--ui-color-text);
    transform: translate(-50%, -50%);
  }
  :global(.folder-dialog [data-dialog-title]),
  :global(.folder-dialog [data-dialog-description]) {
    margin: 0;
  }
  :global(.folder-dialog form) {
    display: grid;
    gap: var(--ui-space-2);
    margin-top: var(--ui-space-4);
  }
  :global(.folder-dialog input) {
    min-height: var(--ui-control-height);
    padding: 0.375rem var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-canvas);
  }
  .folder-dialog-status {
    margin: 0;
    color: var(--ui-color-danger);
    font-size: var(--ui-text-sm);
  }
  .folder-dialog-actions {
    display: flex;
    justify-content: end;
    gap: var(--ui-space-2);
    margin-top: var(--ui-space-2);
  }
  .folder-dialog-actions :global(button),
  .folder-dialog-actions button {
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-canvas);
  }
  .folder-dialog-actions button[type="submit"] {
    border-color: var(--ui-color-accent);
    background: var(--ui-color-accent);
    color: var(--ui-color-accent-contrast);
  }
  .dashboard-workspace {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    min-width: 0;
    min-height: 0;
  }
  :global(.dashboard-document) {
    height: 100%;
    display: grid;
    grid-template-rows: var(--ui-document-tabs-height) minmax(0, 1fr);
    min-width: 0;
    min-height: 0;
  }
  .dashboard-document-tabs-container {
    display: flex;
    align-items: end;
    min-width: 0;
    padding: 0.3125rem var(--ui-space-2) 0;
    border-bottom: 1px solid var(--ui-color-border);
    background: var(--ui-color-border-soft);
  }
  .dashboard-document-tabs-container :global(.dashboard-document-tabs) {
    height: 100%;
    flex: 0 1 auto;
    max-width: calc(100% - 2rem);
    display: flex;
    align-items: end;
    gap: 0.125rem;
    min-width: 0;
    overflow-x: auto;
  }
  .dashboard-document-item {
    position: relative;
    display: flex;
    align-items: end;
    flex: none;
  }
  .dashboard-document-item.drop-target :global(.dashboard-document-tab) {
    border-color: var(--ui-color-accent);
    box-shadow: inset 0 -2px 0 var(--ui-color-accent);
  }
  .dashboard-document-tabs-container :global(.dashboard-document-tab) {
    max-width: 15rem;
    min-width: 8.75rem;
    height: var(--ui-document-tab-height);
    padding: 0 2.125rem 0 0.625rem;
    border: 1px solid var(--ui-color-border);
    border-bottom: 0;
    border-radius: 0.3125rem 0.3125rem 0 0;
    background: var(--ui-color-canvas);
    color: var(--ui-color-text-secondary);
    display: flex;
    align-items: center;
    gap: var(--ui-space-2);
  }
  .dashboard-document-tabs-container
    :global(.dashboard-document-tab[data-state="active"]) {
    height: 2.0625rem;
    background: var(--ui-color-paper);
    color: var(--ui-color-text);
    font-weight: 600;
  }
  .dashboard-document-dot {
    width: var(--ui-space-2);
    height: var(--ui-space-2);
    flex: none;
    border-radius: 50%;
    background: var(--ui-color-text-faint);
  }
  .dashboard-document-tabs-container
    :global(.dashboard-document-tab[data-state="active"]) {
    .dashboard-document-dot {
      background: var(--ui-color-accent);
    }
  }
  .dashboard-document-title {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .dashboard-document-close {
    position: absolute;
    z-index: 1;
    right: var(--ui-space-1);
    bottom: 0.1875rem;
    width: 1.625rem;
    height: 1.625rem;
    border: 0;
    border-radius: var(--ui-radius-md);
    background: transparent;
    color: var(--ui-color-text-faint);
    font-size: 1rem;
    line-height: 1;
  }
  .dashboard-document-close:hover {
    background: var(--ui-color-accent-soft);
    color: var(--ui-color-text);
  }
  .dashboard-document-close:disabled {
    cursor: not-allowed;
    opacity: 0.5;
  }
  .dashboard-document-tabs-container :global(.dashboard-document-add) {
    width: 2rem;
    height: var(--ui-document-tab-height);
    flex: none;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    color: var(--ui-color-text-secondary);
    background: var(--ui-color-canvas);
    display: grid;
    place-items: center;
  }
  .dashboard-document-tabs-container :global(.dashboard-document-add:hover) {
    color: var(--ui-color-text);
    background: var(--ui-color-paper);
  }
  :global(.dashboard-document-create-menu) {
    z-index: 100;
    min-width: 11rem;
    padding: 0.25rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
  }
  :global(.dashboard-document-create-menu [role="menuitem"]) {
    min-height: var(--ui-control-height);
    padding: 0.25rem 0.5rem;
    border-radius: var(--ui-radius-sm);
    display: flex;
    align-items: center;
    gap: var(--ui-space-2);
    outline: 0;
  }
  :global(.dashboard-document-create-menu [role="menuitem"][data-highlighted]) {
    background: var(--ui-color-accent-soft);
  }
  :global(.dashboard-document-panel) {
    min-width: 0;
    min-height: 0;
  }
  .dashboard-workspace-empty {
    grid-row: 2;
    min-height: 0;
    display: grid;
    place-content: center;
    justify-items: center;
    gap: var(--ui-space-3);
    color: var(--ui-color-text-faint);
    background: var(--ui-color-surface);
  }
  .dashboard-workspace-empty p {
    margin: 0;
  }
  @media (max-width: 47.5em) {
    .dashboard-document-tabs-container :global(.dashboard-document-tab) {
      min-width: 6.875rem;
    }
  }
  :global(.dashboard-document[data-orientation="vertical"]) {
    grid-template-columns: minmax(10rem, 16rem) minmax(0, 1fr);
    grid-template-rows: minmax(0, 1fr);

    .dashboard-document-tabs-container {
      flex-direction: column;
      align-items: stretch;
      padding: var(--ui-space-2) 0.3125rem;
      border-right: 1px solid var(--ui-color-border);
      border-bottom: 0;
    }
    :global(.dashboard-document-tabs) {
      width: 100%;
      max-width: none;
      flex: 1 1 auto;
      flex-direction: column;
      align-items: stretch;
      overflow-x: hidden;
      overflow-y: auto;
    }
    .dashboard-document-item {
      width: 100%;
      align-items: center;
    }
    :global(.dashboard-document-tab) {
      width: 100%;
      max-width: none;
      min-width: 0;
      border-bottom: 1px solid var(--ui-color-border);
      border-radius: var(--ui-radius-md);
    }
    :global(.dashboard-document-tab[data-state="active"]) {
      height: var(--ui-document-tab-height);
    }
    .dashboard-document-close {
      top: 50%;
      bottom: auto;
      transform: translateY(-50%);
    }
    :global(.dashboard-document-add) {
      width: 100%;
    }
    :global(.dashboard-document-panel) {
      grid-column: 2;
      grid-row: 1;
    }
    .dashboard-workspace-empty {
      grid-column: 2;
      grid-row: 1;
    }

    @media (max-width: 47.5em) {
      grid-template-columns: minmax(0, 1fr);
      grid-template-rows: var(--ui-document-tabs-height) minmax(0, 1fr);

      .dashboard-document-tabs-container {
        flex-direction: row;
        align-items: end;
        padding: 0.3125rem var(--ui-space-2) 0;
        border-right: 0;
        border-bottom: 1px solid var(--ui-color-border);
      }
      :global(.dashboard-document-tabs) {
        width: auto;
        max-width: calc(100% - 2rem);
        flex: 0 1 auto;
        flex-direction: row;
        align-items: end;
        overflow-x: auto;
        overflow-y: hidden;
      }
      .dashboard-document-item {
        width: auto;
        align-items: end;
      }
      :global(.dashboard-document-tab) {
        width: auto;
        min-width: 6.875rem;
        border-bottom: 0;
        border-radius: 0.3125rem 0.3125rem 0 0;
      }
      .dashboard-document-close {
        top: auto;
        bottom: 0.1875rem;
        transform: none;
      }
      :global(.dashboard-document-add) {
        width: 2rem;
      }
      :global(.dashboard-document-panel) {
        grid-column: auto;
        grid-row: 2;
      }
      .dashboard-workspace-empty {
        grid-column: auto;
        grid-row: 2;
      }
    }
  }

  @media (min-width: 75em) {
    .dashboard-workspace {
      grid-template-columns: minmax(12rem, 16rem) minmax(0, 1fr);
    }
    .dashboard-workspace-outline-collapsed {
      grid-template-columns: 3rem minmax(0, 1fr);
    }
    :global(.dashboard-document),
    :global(.dashboard-document[data-orientation="vertical"]) {
      grid-column: 2;
      grid-row: 1;
      grid-template-columns: minmax(0, 1fr);
      grid-template-rows: var(--ui-document-tabs-height) minmax(0, 1fr);
    }
  }
</style>
