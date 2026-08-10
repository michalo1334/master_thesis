<script lang="ts">
  import type { MissionCapabilityNode } from "../../../contracts.generated";

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
    font-size: var(--ds-text-sm);
    font-weight: 700;
    fill: var(--ds-color-text);
    pointer-events: none;
  }
  .canvas-node-sub {
    font: var(--ds-text-xs) var(--ds-font-mono);
    fill: var(--ds-color-text-muted);
    pointer-events: none;
  }
</style>
