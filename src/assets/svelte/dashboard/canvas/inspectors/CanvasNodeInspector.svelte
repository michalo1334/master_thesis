<script lang="ts">
  import type { Node } from "../../contract";
  import Inspector from "../../workspace/Inspector.svelte";

  interface Props {
    node: Node;
  }

  let { node }: Props = $props();
</script>

<Inspector title="Node inspector">
  <dl class="canvas-node-inspector">
    <div class="canvas-inspector-field">
      <dt>ID</dt>
      <dd>{node.id}</dd>
    </div>
    <div class="canvas-inspector-field">
      <dt>Type</dt>
      <dd>{node.type}</dd>
    </div>
  </dl>
</Inspector>

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
