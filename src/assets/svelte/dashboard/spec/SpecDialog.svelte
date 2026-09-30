<script lang="ts">
  import { Dialog } from "bits-ui";
  import type { Snippet } from "svelte";

  interface Props {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    title: string;
    description: string;
    list: Snippet;
    editor: Snippet;
  }

  let { open, onOpenChange, title, description, list, editor }: Props =
    $props();
</script>

<Dialog.Root {open} {onOpenChange}>
  {#if open}
    <Dialog.Portal>
      <Dialog.Overlay class="spec-overlay" />
      <Dialog.Content class="spec-dialog">
        <Dialog.Title>{title}</Dialog.Title>
        <Dialog.Description>{description}</Dialog.Description>

        <div class="spec-body">
          <section class="spec-pane spec-list-pane">{@render list()}</section>
          <section class="spec-pane spec-editor-pane">
            {@render editor()}
          </section>
        </div>
      </Dialog.Content>
    </Dialog.Portal>
  {/if}
</Dialog.Root>

<style>
  :global(.spec-overlay) {
    position: fixed;
    z-index: 200;
    inset: 0;
    background: color-mix(in srgb, var(--ui-color-nav) 45%, transparent);
  }

  :global(.spec-dialog) {
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
    overflow: auto;
  }

  :global(.spec-dialog [data-dialog-title]) {
    margin: 0;
    font-size: var(--ui-text-xl);
  }

  :global(.spec-dialog [data-dialog-description]) {
    margin: var(--ui-space-2) 0 0;
    color: var(--ui-color-text-secondary);
  }

  .spec-body {
    display: grid;
    grid-template-columns: minmax(12rem, 1fr) minmax(0, 2fr);
    gap: var(--ui-space-3);
    min-height: 0;
    margin-top: var(--ui-space-4);
  }

  .spec-pane {
    display: flex;
    flex-direction: column;
    min-height: 0;
    padding: var(--ui-space-3);
    border: 1px solid var(--ui-color-border-soft);
    border-radius: var(--ui-radius-md);
  }

  @media (max-width: 40rem) {
    .spec-body {
      grid-template-columns: 1fr;
    }
  }
</style>
