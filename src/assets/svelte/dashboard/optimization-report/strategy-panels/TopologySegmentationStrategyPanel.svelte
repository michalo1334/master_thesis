<script lang="ts">
  import type { OptimizationPresentation } from "../optimization-presentation";
  import StrategyPanel from "./StrategyPanel.svelte";
  interface Props {
    presentation: OptimizationPresentation;
  }
  let { presentation }: Props = $props();
</script>

<StrategyPanel
  title="Topology segmentation"
  description="Cuts segment-boundary reachability policies that reduce reachable hosts."
  actions={presentation.actions}
/>
