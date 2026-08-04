<script lang="ts">
  import type { OptimizationAnalysis } from "../to-analysis";
  import StrategyPanel from "./StrategyPanel.svelte";
  interface Props {
    analysis: OptimizationAnalysis;
  }
  let { analysis }: Props = $props();
</script>

<StrategyPanel
  title="Topology segmentation"
  description="Cuts segment-boundary reachability policies that reduce reachable hosts."
  actions={analysis.actions}
/>
