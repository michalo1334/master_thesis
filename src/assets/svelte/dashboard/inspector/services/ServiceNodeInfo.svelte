<script lang="ts">
  import type { ServiceNode } from "../../../contracts.generated";

  interface Props {
    node: ServiceNode;
  }

  let { node }: Props = $props();
</script>

<text class="canvas-node-title" x="28" y="22">{node.data.name}</text>
<text class="canvas-node-sub" x="10" y="60"
  >{node.data.port}/{node.data.protocol}</text
>

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
