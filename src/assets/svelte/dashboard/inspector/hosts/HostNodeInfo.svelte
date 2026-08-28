<script lang="ts">
  import type { HostNode } from "../../../contracts.generated/graph";

  interface Props {
    node: HostNode;
  }

  let { node }: Props = $props();
</script>

<text class="canvas-node-title" x="28" y="22">{node.data.name}</text>

<style>
  .canvas-node-title {
    font-size: var(--ui-text-sm);
    font-weight: 700;
    fill: var(--ui-color-text);
    pointer-events: none;
  }
</style>
