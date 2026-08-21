<script lang="ts">
  import type { OptimizationReportDocument } from "../../optimization-report/OptimizationReportDocument.svelte";
  import type { SimulationReportDocument } from "../../simulation-report/SimulationReportDocument.svelte";
  import Inspector from "../../../ui-kit/layout/Inspector.svelte";

  interface Props {
    document: SimulationReportDocument | OptimizationReportDocument;
  }

  let { document }: Props = $props();
</script>

<Inspector title="Report">
  <p class="report-title">{document.title}</p>
</Inspector>

<style>
  .report-title {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }
</style>
