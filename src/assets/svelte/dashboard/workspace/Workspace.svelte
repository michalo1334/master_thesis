<script lang="ts">
  import { Dialog, DropdownMenu } from "bits-ui";
  import type { Snippet } from "svelte";
  import { Icon } from "../../ui-kit/primitives";
  import {
    DocumentOutline,
    Workspace as WorkspaceShell,
    type OutlineRow,
  } from "../../ui-kit/workspace";
  import {
    buildDashboardRows,
    dispatchDashboardOutlineSelect,
  } from "./build-dashboard-rows";
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

  let outlineRows: readonly OutlineRow<string, string>[] = $derived(
    buildDashboardRows(model.documents, model.folders, model.graphSummaries),
  );

  let outlineCollapsed = $state(false);
  let folderDialogOpen = $state(false);
  let folderName = $state("");
  let isCreatingFolder = $state(false);

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

  function selectOutline(id: string, event: MouseEvent): void {
    dispatchDashboardOutlineSelect(model.documents, id, event, (documentId) =>
      model.selectDocument(documentId),
    );
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
    onSelect={selectOutline}
    collapsed={outlineCollapsed}
    onCollapsedChange={(collapsed) => (outlineCollapsed = collapsed)}
    onDrop={(graphId, folderId) => void onMoveGraph(graphId, folderId)}
  >
    {#snippet rowSnippet(row)}
      {#if row.type === "header" && row.kind === "folder"}
        <div
          class="document-outline-folder-header"
          role="heading"
          aria-level="2"
        >
          <Icon name="folder" size={16} />
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
      {:else if row.type === "item" && row.drag}
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
                onclick={() => void onMoveGraph(row.drag!.data, null)}
              >
                Move to root
              </DropdownMenu.Item>
              {#each model.folders as folder (folder.id)}
                <DropdownMenu.Item
                  onclick={() => void onMoveGraph(row.drag!.data, folder.id)}
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

  <WorkspaceShell {model} {orientation} {content}>
    {#snippet tabActions()}
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
    {/snippet}
  </WorkspaceShell>
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
  :global(.dashboard-document-add) {
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
  :global(.dashboard-document-add:hover) {
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
  :global(
    .dashboard-document[data-orientation="vertical"] .dashboard-document-add
  ) {
    width: 100%;
  }
  @media (max-width: 47.5em) {
    :global(
      .dashboard-document[data-orientation="vertical"] .dashboard-document-add
    ) {
      width: 2rem;
    }
  }

  @media (min-width: 75em) {
    .dashboard-workspace {
      grid-template-columns: minmax(12rem, 16rem) minmax(0, 1fr);
    }
    .dashboard-workspace-outline-collapsed {
      grid-template-columns: 3rem minmax(0, 1fr);
    }
    .dashboard-workspace :global(.workspace) {
      grid-column: 2;
      grid-row: 1;
    }
  }
</style>
