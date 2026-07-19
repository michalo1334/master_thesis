<script lang="ts">
  import type { Selectable } from "../../contract";
  import Inspector from "../../workspace/Inspector.svelte";

  interface Props {
    selectable: Selectable;
  }

  let { selectable }: Props = $props();

  let edge = $derived(!("view_data" in selectable) ? selectable : null);
</script>

{#if edge}
  <Inspector title="Edge inspector">
    <dl class="canvas-edge-inspector">
      <div class="canvas-inspector-field">
        <dt>ID</dt>
        <dd>{edge.id}</dd>
      </div>
      <div class="canvas-inspector-field">
        <dt>Type</dt>
        <dd>{edge.type}</dd>
      </div>
      <div class="canvas-inspector-field">
        <dt>From</dt>
        <dd>{edge.from_id}</dd>
      </div>
      <div class="canvas-inspector-field">
        <dt>To</dt>
        <dd>{edge.to_id}</dd>
      </div>
    </dl>
  </Inspector>
{/if}

<style>
  .canvas-edge-inspector {
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
