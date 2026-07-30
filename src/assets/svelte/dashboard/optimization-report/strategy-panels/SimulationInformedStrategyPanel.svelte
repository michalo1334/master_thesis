<script lang="ts">
  import type { OptimizationAnalysis } from "../to-analysis";
  import StrategyPanel from "./StrategyPanel.svelte";
  interface Props {
    analysis: OptimizationAnalysis;
  }
  let { analysis }: Props = $props();
</script>

<StrategyPanel
  title="Simulation-informed prioritization"
  description="Ranks defenses by simulated blast-radius reduction."
  actions={analysis.actions}
/>
