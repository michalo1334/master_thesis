<script lang="ts">
  import type { OptimizationAnalysis } from "../to-analysis";
  import StatisticalChart from "../../simulation-report/StatisticalChart.svelte";
  import { cvssOptions } from "../chart-options";
  import StrategyPanel from "./StrategyPanel.svelte";
  interface Props {
    analysis: OptimizationAnalysis;
  }
  let { analysis }: Props = $props();
  let hasCvssScores = $derived(
    analysis.actions.some((action) => action.cvss_score != null),
  );
</script>

<StrategyPanel
  title="CVSS prioritization"
  description="Prioritizes patches by vulnerability severity."
  actions={analysis.actions}
/>

{#if hasCvssScores}
  <div class="cvss-chart">
    <StatisticalChart
      id="optimization-cvss-scores"
      title="Selected vulnerability severity"
      takeaway="Shows CVSS scores for the selected defenses."
      ariaLabel="CVSS score by selected defense"
      option={cvssOptions(analysis.actions)}
    />
  </div>
{/if}

<style>
  .cvss-chart {
    max-width: 62rem;
    margin-top: var(--ui-space-3);
  }
</style>
