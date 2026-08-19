<script lang="ts" generics="D extends UiWorkspaceDocument">
  import { Tabs } from "bits-ui";
  import type { Snippet } from "svelte";
  import Icon from "../primitives/Icon.svelte";
  import type { GenericWorkspaceModel } from "./WorkspaceModel.svelte";
  import type { UiWorkspaceDocument } from "./WorkspaceDocument.svelte";

  interface Props {
    model: GenericWorkspaceModel<D>;
    orientation?: "horizontal" | "vertical";
    content?: Snippet<[D]>;
    tabActions?: Snippet;
  }

  let {
    model,
    orientation = "horizontal",
    content = undefined,
    tabActions = undefined,
  }: Props = $props();

  let activeDocument = $derived(model.activeDocument);
  let draggedDocumentId = $state<string>();
  let dropTargetId = $state<string>();

  function closeDocument(event: MouseEvent, id: string) {
    event.stopPropagation();
    model.closeDocument(id);
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

<div class="workspace">
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
      {@render tabActions?.()}
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
</div>

<style>
  .workspace {
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
</style>
