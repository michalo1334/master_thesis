<script lang="ts">
  import type { NetworkSegmentNode } from "../../../contracts.generated/graph";

  interface Props {
    node: NetworkSegmentNode;
  }

  let { node }: Props = $props();
</script>

<text class="canvas-node-title" x="28" y="22">{node.data.name}</text>
{#if node.data.cidr}
  <text class="canvas-node-sub" x="10" y="43">{node.data.cidr}</text>
{/if}

<style>
  .canvas-node-title {
    font-size: var(--ui-text-sm);
    font-weight: 700;
    fill: var(--ui-color-text);
    pointer-events: none;
  }
  .canvas-node-sub {
    font: var(--ui-text-xs) var(--ui-font-mono);
    fill: var(--ui-color-text-muted);
    pointer-events: none;
  }
</style>
