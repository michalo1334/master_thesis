<script lang="ts">
  import { Tabs } from "bits-ui";
  import type { DashboardDocument } from "./types";

  interface Props {
    documents: DashboardDocument[];
    onClose: (id: string) => void;
  }

  let { documents, onClose }: Props = $props();
</script>

<div class="dashboard-document-tabs-container">
  <Tabs.List class="dashboard-document-tabs" aria-label="Open topology documents">
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
          disabled={documents.length === 1}
          onclick={() => onClose(document.id)}
        >×</button>
      </div>
    {/each}
  </Tabs.List>
</div>

<style>
  .dashboard-document-tabs-container { min-width: 0; overflow: hidden; }
  .dashboard-document-tabs-container :global(.dashboard-document-tabs) { height: var(--ds-document-tabs-height); display: flex; align-items: end; gap: 0.125rem; padding: 0.3125rem var(--ds-space-2) 0; overflow: hidden; background: #dfe5ec; border-bottom: 1px solid #aeb8c5; }
  .dashboard-document-item { position: relative; display: flex; align-items: end; }
  .dashboard-document-tabs-container :global(.dashboard-document-tab) { max-width: 15rem; min-width: 8.75rem; height: var(--ds-document-tab-height); padding: 0 2.125rem 0 0.625rem; border: 1px solid #b7c0cc; border-bottom: 0; border-radius: 0.3125rem 0.3125rem 0 0; background: #edf1f5; color: var(--ds-color-text-secondary); display: flex; align-items: center; gap: var(--ds-space-2); }
  .dashboard-document-tabs-container :global(.dashboard-document-tab[data-state="active"]) { height: 2.0625rem; background: var(--ds-color-paper); color: var(--ds-color-text); font-weight: 600; }
  .dashboard-document-dot { width: var(--ds-space-2); height: var(--ds-space-2); flex: none; border-radius: 50%; background: #a0acba; }
  .dashboard-document-tabs-container :global(.dashboard-document-tab[data-state="active"] .dashboard-document-dot) { background: #2d75d5; }
  .dashboard-document-title { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .dashboard-document-close { position: absolute; z-index: 1; right: var(--ds-space-1); bottom: 0.1875rem; width: 1.625rem; height: 1.625rem; border: 0; border-radius: var(--ds-radius-md); background: transparent; color: var(--ds-color-text-faint); font-size: 1rem; line-height: 1; }
  .dashboard-document-close:hover:not(:disabled) { background: var(--ds-color-accent-soft); color: var(--ds-color-text); }
  .dashboard-document-close:disabled { cursor: not-allowed; opacity: .35; }

  @media (max-width: 47.5em) {
    .dashboard-document-tabs-container :global(.dashboard-document-tab) { min-width: 6.875rem; }
  }
</style>
