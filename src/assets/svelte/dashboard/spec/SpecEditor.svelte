<script lang="ts">
  import { Tabs } from "bits-ui";
  import type { Snippet } from "svelte";
  import type { ManifestError } from "../../contracts.generated/dashboard/evaluation";
  import type { SpecAction, SpecTab } from "./spec.types";

  interface Props {
    titleLabel: string;
    title: string;
    onTitleInput: (value: string) => void;
    editorLabel: string;
    editorText: string;
    onEditorInput: (value: string) => void;
    tabs: readonly SpecTab[];
    activeTab: string;
    onTabChange: (value: string) => void;
    tabsAriaLabel: string;
    errors: readonly ManifestError[];
    statusMessage: string;
    isBusy: boolean;
    actions: readonly SpecAction[];
    tabContent: Snippet<[string]>;
  }

  let {
    titleLabel,
    title,
    onTitleInput,
    editorLabel,
    editorText,
    onEditorInput,
    tabs,
    activeTab,
    onTabChange,
    tabsAriaLabel,
    errors,
    statusMessage,
    isBusy,
    actions,
    tabContent,
  }: Props = $props();
</script>

<div class="spec-editor">
  <label class="spec-field">
    <span class="spec-field-label">{titleLabel}</span>
    <input
      class="spec-title-input"
      type="text"
      value={title}
      disabled={isBusy}
      oninput={(event) => onTitleInput(event.currentTarget.value)}
    />
  </label>

  <Tabs.Root
    class="spec-editor-tabs"
    value={activeTab}
    onValueChange={onTabChange}
  >
    <Tabs.List class="spec-editor-tab-list" aria-label={tabsAriaLabel}>
      {#each tabs as tab (tab.value)}
        <Tabs.Trigger
          class="spec-editor-tab"
          value={tab.value}
          disabled={isBusy}
        >
          {tab.label}
        </Tabs.Trigger>
      {/each}
    </Tabs.List>
    {#each tabs as tab (tab.value)}
      <Tabs.Content class="spec-editor-tab-panel" value={tab.value}>
        {#if tab.value === "json"}
          <label class="spec-field">
            <span class="spec-field-label">{editorLabel}</span>
            <textarea
              class="spec-editor-text"
              value={editorText}
              disabled={isBusy}
              oninput={(event) => onEditorInput(event.currentTarget.value)}
              spellcheck="false"></textarea>
          </label>
        {:else}
          {@render tabContent(tab.value)}
        {/if}
      </Tabs.Content>
    {/each}
  </Tabs.Root>

  {#if errors.length > 0}
    <ul class="spec-errors" role="alert">
      {#each errors as error (error.path + error.message)}
        <li>{error.path}: {error.message}</li>
      {/each}
    </ul>
  {/if}
  {#if statusMessage}
    <p class="spec-status" role="status">{statusMessage}</p>
  {/if}

  {#if actions.length > 0}
    <div class="spec-actions">
      {#each actions as action (action.label)}
        <button
          class="spec-button"
          class:spec-confirm={action.variant === "confirm"}
          type="button"
          disabled={action.disabled}
          onclick={action.onAction}
        >
          {action.label}
        </button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .spec-editor {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
    gap: var(--ui-space-3);
  }

  :global(.spec-editor-tabs) {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
    gap: var(--ui-space-2);
  }

  :global(.spec-editor-tab-list) {
    display: flex;
    gap: var(--ui-space-1);
  }

  :global(.spec-editor-tab) {
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-surface);
    color: inherit;
    font: inherit;
    cursor: pointer;
  }

  :global(.spec-editor-tab[data-state="active"]) {
    border-color: var(--ui-color-accent);
    color: var(--ui-color-accent);
  }

  :global(.spec-editor-tab-panel) {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
  }

  .spec-field {
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-1);
  }

  .spec-field-label {
    font-size: var(--ui-text-sm);
    color: var(--ui-color-text-secondary);
  }

  .spec-title-input {
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-surface);
    color: inherit;
  }

  .spec-editor-text {
    min-height: 16rem;
    flex: 1;
    padding: 0.5rem 0.75rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-surface);
    color: inherit;
    font: 0.8125rem / 1.4 var(--ui-font-mono, monospace);
    resize: none;
  }

  .spec-errors {
    margin: 0;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-danger-bg, var(--ui-color-warning-bg));
    color: var(--ui-color-danger-text, var(--ui-color-warning-text));
    font-size: var(--ui-text-sm);
    list-style: none;
  }

  .spec-status {
    margin: 0;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-warning-bg);
    color: var(--ui-color-warning-text);
    font-size: var(--ui-text-sm);
  }

  .spec-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--ui-space-2);
  }

  .spec-button {
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-surface);
    color: inherit;
  }

  .spec-confirm {
    border-color: var(--ui-color-accent);
    background: var(--ui-color-accent);
    color: var(--ui-color-paper);
  }

  .spec-button:disabled,
  .spec-title-input:disabled,
  .spec-editor-text:disabled {
    cursor: default;
    opacity: 0.55;
  }
</style>
