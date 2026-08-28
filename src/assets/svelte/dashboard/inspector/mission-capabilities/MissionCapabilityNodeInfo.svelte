<script lang="ts">
  import type { MissionCapabilityNode } from "../../../contracts.generated/graph";

  interface Props {
    node: MissionCapabilityNode;
  }

  let { node }: Props = $props();
</script>

<text class="canvas-node-title" x="28" y="22">{node.data.name}</text>
<text class="canvas-node-sub" x="10" y="60"
  >min support: {node.data.min_operational_support}</text
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
