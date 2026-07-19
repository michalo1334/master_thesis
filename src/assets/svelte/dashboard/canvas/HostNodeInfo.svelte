<script lang="ts">
  import type { Node } from "../contract";

  interface Props {
    node: Node;
  }

  let { node }: Props = $props();
</script>

<text class="canvas-node-title" x="28" y="22">{node.data.name}</text>

<style>
  .canvas-node-title {
    font-size: var(--ds-text-sm);
    font-weight: 700;
    fill: #1b2738;
    pointer-events: none;
  }
</style>
