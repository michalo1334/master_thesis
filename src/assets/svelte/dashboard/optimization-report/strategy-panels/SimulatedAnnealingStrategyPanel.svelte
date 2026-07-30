<script lang="ts">
  import type { OptimizationAnalysis } from "../to-analysis";
  import StrategyPanel from "./StrategyPanel.svelte";
  interface Props {
    analysis: OptimizationAnalysis;
  }
  let { analysis }: Props = $props();
</script>

<StrategyPanel
  title="Simulated annealing"
  description="Searches defense combinations for a lower simulated blast radius."
  actions={analysis.actions}
/>
