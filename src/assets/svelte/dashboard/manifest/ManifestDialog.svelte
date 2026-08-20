<script lang="ts">
  import { Dialog } from "bits-ui";
  import type { ManifestModel } from "./ManifestModel.svelte";

  interface Props {
    model: ManifestModel;
  }

  let { model }: Props = $props();

  function handleOpenChange(open: boolean): void {
    if (!open) model.closeDialog();
  }
</script>

<Dialog.Root open={model.open} onOpenChange={handleOpenChange}>
  {#if model.open}
    <Dialog.Portal>
      <Dialog.Overlay class="manifest-overlay" />
      <Dialog.Content class="manifest-dialog">
        <Dialog.Title>Evaluation manifests</Dialog.Title>
        <Dialog.Description>
          Save and run reproducible evaluations from a raw JSON manifest.
        </Dialog.Description>

        <div class="manifest-body">
          <section class="manifest-pane manifest-list-pane">
            <div class="manifest-pane-header">
              <h2 class="manifest-pane-title">Saved manifests</h2>
              <button
                class="manifest-button"
                type="button"
                disabled={model.isBusy}
                onclick={() => model.addManifest()}
              >
                Add
              </button>
            </div>
            <ul class="manifest-list">
              {#each model.manifests as manifest (manifest.id)}
                <li>
                  <button
                    class="manifest-item"
                    class:manifest-item-active={manifest.id ===
                      model.selectedId}
                    type="button"
                    disabled={model.isBusy}
                    onclick={() => model.selectManifest(manifest.id)}
                  >
                    {manifest.title}
                  </button>
                </li>
              {/each}
            </ul>
            {#if model.manifests.length === 0}
              <p class="manifest-empty">No saved manifests.</p>
            {/if}
          </section>

          <section class="manifest-pane manifest-editor-pane">
            <label class="manifest-field">
              <span class="manifest-field-label">Title</span>
              <input
                class="manifest-title-input"
                type="text"
                value={model.title}
                disabled={model.isBusy}
                oninput={(event) => (model.title = event.currentTarget.value)}
              />
            </label>
            <label class="manifest-field">
              <span class="manifest-field-label">Manifest JSON</span>
              <textarea
                class="manifest-editor"
                value={model.editorText}
                disabled={model.isBusy}
                oninput={(event) =>
                  (model.editorText = event.currentTarget.value)}
                spellcheck="false"></textarea>
            </label>

            {#if model.errors.length > 0}
              <ul class="manifest-errors" role="alert">
                {#each model.errors as error (error.path + error.message)}
                  <li>{error.path}: {error.message}</li>
                {/each}
              </ul>
            {/if}
            {#if model.statusMessage}
              <p class="manifest-status" role="status">{model.statusMessage}</p>
            {/if}

            <div class="manifest-actions">
              <button
                class="manifest-button"
                type="button"
                disabled={!model.canSave}
                onclick={() => model.save()}
              >
                Save
              </button>
              <button
                class="manifest-button manifest-confirm"
                type="button"
                disabled={!model.canStart}
                onclick={() => model.start()}
              >
                Start evaluation
              </button>
            </div>
          </section>
        </div>
      </Dialog.Content>
    </Dialog.Portal>
  {/if}
</Dialog.Root>

<style>
  :global(.manifest-overlay) {
    position: fixed;
    z-index: 200;
    inset: 0;
    background: color-mix(in srgb, var(--ui-color-nav) 45%, transparent);
  }

  :global(.manifest-dialog) {
    position: fixed;
    z-index: 201;
    top: 50%;
    left: 50%;
    width: min(78rem, calc(100vw - 2rem));
    max-height: calc(100dvh - 2rem);
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr);
    padding: var(--ui-space-4);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-lg);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
    color: var(--ui-color-text);
    transform: translate(-50%, -50%);
  }

  :global(.manifest-dialog [data-dialog-title]) {
    margin: 0;
    font-size: var(--ui-text-xl);
  }

  :global(.manifest-dialog [data-dialog-description]) {
    margin: var(--ui-space-2) 0 0;
    color: var(--ui-color-text-secondary);
  }

  .manifest-body {
    display: grid;
    grid-template-columns: minmax(12rem, 1fr) minmax(0, 2fr);
    gap: var(--ui-space-3);
    min-height: 0;
    margin-top: var(--ui-space-4);
  }

  .manifest-pane {
    display: flex;
    flex-direction: column;
    min-height: 0;
    padding: var(--ui-space-3);
    border: 1px solid var(--ui-color-border-soft);
    border-radius: var(--ui-radius-md);
  }

  .manifest-pane-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--ui-space-2);
    margin-bottom: var(--ui-space-2);
  }

  .manifest-pane-title {
    margin: 0;
    font-size: var(--ui-text-base);
  }

  .manifest-list {
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-1);
    min-height: 0;
    margin: 0;
    padding: 0;
    list-style: none;
    overflow: auto;
  }

  .manifest-item {
    width: 100%;
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid transparent;
    border-radius: var(--ui-radius-md);
    background: transparent;
    color: inherit;
    text-align: left;
  }

  .manifest-item-active {
    border-color: var(--ui-color-accent);
    background: color-mix(in srgb, var(--ui-color-accent) 12%, transparent);
  }

  .manifest-empty {
    margin: var(--ui-space-2) 0 0;
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }

  .manifest-editor-pane {
    gap: var(--ui-space-3);
  }

  .manifest-field {
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-1);
  }

  .manifest-field-label {
    font-size: var(--ui-text-sm);
    color: var(--ui-color-text-secondary);
  }

  .manifest-title-input {
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-surface);
    color: inherit;
  }

  .manifest-editor {
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

  .manifest-errors {
    margin: 0;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-danger-bg, var(--ui-color-warning-bg));
    color: var(--ui-color-danger-text, var(--ui-color-warning-text));
    font-size: var(--ui-text-sm);
    list-style: none;
  }

  .manifest-status {
    margin: 0;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-warning-bg);
    color: var(--ui-color-warning-text);
    font-size: var(--ui-text-sm);
  }

  .manifest-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--ui-space-2);
  }

  .manifest-button {
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-surface);
    color: inherit;
  }

  .manifest-confirm {
    border-color: var(--ui-color-accent);
    background: var(--ui-color-accent);
    color: var(--ui-color-paper);
  }

  .manifest-item:disabled,
  .manifest-button:disabled,
  .manifest-title-input:disabled,
  .manifest-editor:disabled {
    cursor: default;
    opacity: 0.55;
  }

  @media (max-width: 40rem) {
    .manifest-body {
      grid-template-columns: 1fr;
    }
  }
</style>
