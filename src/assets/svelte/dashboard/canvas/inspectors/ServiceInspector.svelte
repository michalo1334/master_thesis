<script lang="ts">
  import type { Selectable } from "../../contract";
  import Inspector from "../../workspace/Inspector.svelte";

  interface Props {
    selectable: Selectable;
  }

  let { selectable }: Props = $props();

  let node = $derived("view_data" in selectable ? selectable : null);
</script>

{#if node}
  <Inspector title="Service">
    <dl class="canvas-node-inspector">
      <div class="canvas-inspector-field">
        <dt>Name</dt>
        <dd>{node.data.name}</dd>
      </div>
      <div class="canvas-inspector-field">
        <dt>Protocol</dt>
        <dd>{node.data.protocol}</dd>
      </div>
      <div class="canvas-inspector-field">
        <dt>Port</dt>
        <dd>{node.data.port}</dd>
      </div>
      <div class="canvas-inspector-field">
        <dt>Version</dt>
        <dd>{node.data.version ?? "—"}</dd>
      </div>
    </dl>
  </Inspector>
{/if}

<style>
  .canvas-node-inspector {
    margin: 0;
    display: grid;
    gap: var(--ds-space-3);
  }
  .canvas-inspector-field {
    display: grid;
    gap: var(--ds-space-1);
  }
  .canvas-inspector-field dt {
    font-size: var(--ds-text-xs);
    font-weight: 600;
    color: var(--ds-color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .canvas-inspector-field dd {
    margin: 0;
    font-family: var(--ds-font-mono);
    font-size: var(--ds-text-sm);
    word-break: break-all;
  }
</style>
