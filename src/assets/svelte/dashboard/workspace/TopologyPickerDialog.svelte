<script lang="ts">
  import { Dialog } from "bits-ui";
</script>

<Dialog.Root>
  <Dialog.Portal>
    <Dialog.Overlay class="topology-picker-overlay" />
    <Dialog.Content class="topology-picker-dialog">
      <Dialog.Title>Open topology</Dialog.Title>
      <Dialog.Description>
        Select a saved network topology to open in the workspace.
      </Dialog.Description>

      <div class="topology-picker-list" aria-label="Saved topologies"></div>

      <Dialog.Close
        class="topology-picker-close"
        aria-label="Close topology picker"
      >
        ×
      </Dialog.Close>
    </Dialog.Content>
  </Dialog.Portal>
</Dialog.Root>

<style>
  :global(.topology-picker-overlay) {
    position: fixed;
    z-index: 200;
    inset: 0;
    background: rgb(20 31 47 / 45%);
  }
  :global(.topology-picker-dialog) {
    position: fixed;
    z-index: 201;
    top: 50%;
    left: 50%;
    width: min(32rem, calc(100vw - 2rem));
    max-height: min(36rem, calc(100dvh - 2rem));
    overflow: auto;
    padding: 1.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-lg);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
    color: var(--ds-color-text);
    transform: translate(-50%, -50%);
  }
  :global(.topology-picker-dialog [data-dialog-title]) {
    margin: 0;
    font-size: var(--ds-text-xl);
  }
  :global(.topology-picker-dialog [data-dialog-description]) {
    margin: var(--ds-space-2) 0 0;
    color: var(--ds-color-text-secondary);
  }
  .topology-picker-list {
    display: grid;
    gap: var(--ds-space-2);
    margin-top: var(--ds-space-4);
  }
  .topology-picker-item {
    width: 100%;
    padding: var(--ds-space-3);
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-surface);
    color: inherit;
    text-align: left;
  }
  .topology-picker-item:hover {
    border-color: var(--ds-color-focus);
    background: var(--ds-color-accent-soft);
  }
  .topology-picker-title,
  .topology-picker-counts {
    display: block;
  }
  .topology-picker-title {
    font-weight: 600;
  }
  .topology-picker-counts {
    margin-top: var(--ds-space-1);
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
    font-variant-numeric: tabular-nums;
  }
  .topology-picker-empty {
    margin: 0;
    padding: var(--ds-space-4);
    color: var(--ds-color-text-secondary);
    text-align: center;
  }
  :global(.topology-picker-close) {
    position: absolute;
    top: var(--ds-space-2);
    right: var(--ds-space-2);
    display: grid;
    width: 2rem;
    height: 2rem;
    place-items: center;
    border: 0;
    border-radius: var(--ds-radius-sm);
    background: transparent;
    color: var(--ds-color-text-secondary);
    font-size: 1.5rem;
    line-height: 1;
  }
  :global(.topology-picker-close:hover) {
    background: var(--ds-color-accent-soft);
    color: var(--ds-color-text);
  }
</style>
