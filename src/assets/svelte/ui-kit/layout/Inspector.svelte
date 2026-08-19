<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    title?: string;
    children: Snippet;
  }

  let { title = "Inspector", children }: Props = $props();
</script>

<aside class="dashboard-inspector" aria-label={title}>
  <header class="dashboard-inspector-header">
    <h2>{title}</h2>
  </header>
  <div class="dashboard-inspector-content">
    {@render children()}
  </div>
</aside>

<style>
  .dashboard-inspector {
    min-width: 0;
    display: flex;
    flex-direction: column;
    border-left: 1px solid var(--ui-color-border);
    background: var(--ui-color-paper);
  }
  .dashboard-inspector-header {
    min-height: var(--ui-inspector-header-height);
    padding: 0 var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border);
    display: flex;
    align-items: center;
  }
  .dashboard-inspector-header h2 {
    margin: 0;
    font-size: var(--ui-text-lg);
  }
  .dashboard-inspector-content {
    min-height: 0;
    padding: var(--ui-space-3);
    overflow: auto;
  }
</style>
