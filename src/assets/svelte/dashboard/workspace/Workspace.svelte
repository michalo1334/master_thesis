<script lang="ts">
  import { DropdownMenu, Tabs } from "bits-ui";
  import type { Snippet } from "svelte";
  import Icon from "../controls/Icon.svelte";
  import type { IconName } from "../types";
  import type {
    WorkspaceDocument,
    DocumentKind,
  } from "./WorkspaceDocument.svelte";

  export interface WorkspaceDocumentType {
    id: DocumentKind;
    label: string;
    icon?: IconName;
  }

  export type WorkspaceOrientation = "horizontal" | "vertical";

  interface Props {
    documents?: readonly WorkspaceDocument[];
    activeDocumentId?: string;
    orientation?: WorkspaceOrientation;
    onActiveDocumentChange?: (id: string) => void;
    onCloseDocument?: (id: string) => void;
    documentTypes?: readonly WorkspaceDocumentType[];
    onCreateDocument?: (typeId: DocumentKind) => void;
    inspector?: Snippet;
    content?: Snippet<[WorkspaceDocument]>;
  }

  let {
    documents = [],
    activeDocumentId = undefined,
    orientation = "horizontal",
    onActiveDocumentChange = () => {},
    onCloseDocument = () => {},
    documentTypes = [],
    onCreateDocument = () => {},
    inspector = undefined,
    content = undefined,
  }: Props = $props();

  let activeDocument = $derived(
    documents.find((document) => document.id === activeDocumentId),
  );

  function closeDocument(event: MouseEvent, id: string) {
    event.stopPropagation();
    onCloseDocument(id);
  }
</script>

<main class={["dashboard-workspace", "dashboard-workspace-with-inspector"]}>
  <Tabs.Root
    class="dashboard-document"
    {orientation}
    value={activeDocumentId}
    onValueChange={onActiveDocumentChange}
    loop
  >
    <div class="dashboard-document-tabs-container">
      <Tabs.List class="dashboard-document-tabs" aria-label="Open documents">
        {#each documents as document (document.id)}
          <div class="dashboard-document-item">
            <Tabs.Trigger class="dashboard-document-tab" value={document.id}>
              <span class="dashboard-document-dot" aria-hidden="true"></span>
              <span class="dashboard-document-title">{document.title}</span>
            </Tabs.Trigger>
            <button
              type="button"
              class="dashboard-document-close"
              aria-label={`Close ${document.title}`}
              onclick={(event) => closeDocument(event, document.id)}>×</button
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
            {#each documentTypes as documentType (documentType.id)}
              <DropdownMenu.Item
                onclick={() => onCreateDocument(documentType.id)}
              >
                {#if documentType.icon}
                  <Icon name={documentType.icon} size={16} />
                {/if}
                <span>{documentType.label}</span>
              </DropdownMenu.Item>
            {/each}
          </DropdownMenu.Content>
        </DropdownMenu.Portal>
      </DropdownMenu.Root>
    </div>

    {#if activeDocument}
      <Tabs.Content class="dashboard-document-panel" value={activeDocument.id}>
        {@render content?.(activeDocument)}
      </Tabs.Content>
    {/if}

    {#if documents.length === 0}
      <section class="dashboard-workspace-empty" aria-label="No open documents">
        <p>No documents opened</p>
      </section>
    {/if}
  </Tabs.Root>

  {@render inspector?.()}
</main>

<style>
  .dashboard-workspace {
    grid-area: workspace;
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    min-width: 0;
    min-height: 0;
  }
  .dashboard-workspace-with-inspector {
    grid-template-columns: minmax(0, 1fr) var(--ds-inspector-width);
  }
  :global(.dashboard-document) {
    grid-column: 1;
    height: 100%;
    display: grid;
    grid-template-rows: var(--ds-document-tabs-height) minmax(0, 1fr);
    min-width: 0;
    min-height: 0;
  }
  .dashboard-workspace :global(.dashboard-inspector) {
    grid-column: 2;
  }
  .dashboard-document-tabs-container {
    display: flex;
    align-items: end;
    min-width: 0;
    padding: 0.3125rem var(--ds-space-2) 0;
    border-bottom: 1px solid var(--ds-color-border);
    background: var(--ds-color-border-soft);
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
  .dashboard-document-tabs-container :global(.dashboard-document-tab) {
    max-width: 15rem;
    min-width: 8.75rem;
    height: var(--ds-document-tab-height);
    padding: 0 2.125rem 0 0.625rem;
    border: 1px solid var(--ds-color-border);
    border-bottom: 0;
    border-radius: 0.3125rem 0.3125rem 0 0;
    background: var(--ds-color-canvas);
    color: var(--ds-color-text-secondary);
    display: flex;
    align-items: center;
    gap: var(--ds-space-2);
  }
  .dashboard-document-tabs-container
    :global(.dashboard-document-tab[data-state="active"]) {
    height: 2.0625rem;
    background: var(--ds-color-paper);
    color: var(--ds-color-text);
    font-weight: 600;
  }
  .dashboard-document-dot {
    width: var(--ds-space-2);
    height: var(--ds-space-2);
    flex: none;
    border-radius: 50%;
    background: var(--ds-color-text-faint);
  }
  .dashboard-document-tabs-container
    :global(.dashboard-document-tab[data-state="active"]) {
    .dashboard-document-dot {
      background: var(--ds-color-accent);
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
    right: var(--ds-space-1);
    bottom: 0.1875rem;
    width: 1.625rem;
    height: 1.625rem;
    border: 0;
    border-radius: var(--ds-radius-md);
    background: transparent;
    color: var(--ds-color-text-faint);
    font-size: 1rem;
    line-height: 1;
  }
  .dashboard-document-close:hover {
    background: var(--ds-color-accent-soft);
    color: var(--ds-color-text);
  }
  .dashboard-document-tabs-container :global(.dashboard-document-add) {
    width: 2rem;
    height: var(--ds-document-tab-height);
    flex: none;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    color: var(--ds-color-text-secondary);
    background: var(--ds-color-canvas);
    display: grid;
    place-items: center;
  }
  .dashboard-document-tabs-container :global(.dashboard-document-add:hover) {
    color: var(--ds-color-text);
    background: var(--ds-color-paper);
  }
  :global(.dashboard-document-create-menu) {
    z-index: 100;
    min-width: 11rem;
    padding: 0.25rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
  }
  :global(.dashboard-document-create-menu [role="menuitem"]) {
    min-height: var(--ds-control-height);
    padding: 0.25rem 0.5rem;
    border-radius: var(--ds-radius-sm);
    display: flex;
    align-items: center;
    gap: var(--ds-space-2);
    outline: 0;
  }
  :global(.dashboard-document-create-menu [role="menuitem"][data-highlighted]) {
    background: var(--ds-color-accent-soft);
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
    gap: var(--ds-space-3);
    color: var(--ds-color-text-faint);
    background: var(--ds-color-surface);
  }
  .dashboard-workspace-empty p {
    margin: 0;
  }
  @media (max-width: 47.5em) {
    .dashboard-workspace-with-inspector {
      grid-template-columns: minmax(0, 1fr);
    }
    .dashboard-workspace :global(.dashboard-inspector) {
      display: none;
    }
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
      padding: var(--ds-space-2) 0.3125rem;
      border-right: 1px solid var(--ds-color-border);
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
      border-bottom: 1px solid var(--ds-color-border);
      border-radius: var(--ds-radius-md);
    }
    :global(.dashboard-document-tab[data-state="active"]) {
      height: var(--ds-document-tab-height);
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
      grid-template-rows: var(--ds-document-tabs-height) minmax(0, 1fr);

      .dashboard-document-tabs-container {
        flex-direction: row;
        align-items: end;
        padding: 0.3125rem var(--ds-space-2) 0;
        border-right: 0;
        border-bottom: 1px solid var(--ds-color-border);
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
</style>
