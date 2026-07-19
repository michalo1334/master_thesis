<script lang="ts">
  import type { KpiMetric } from "./types";

  interface Props {
    metrics: readonly KpiMetric[];
  }

  let { metrics }: Props = $props();
</script>

<section
  class="statistics-kpis"
  aria-label="Simulation key performance indicators"
>
  {#each metrics as metric (metric.label)}
    <article class={`statistics-kpi statistics-kpi-${metric.tone}`}>
      <p class="statistics-kpi-label">{metric.label}</p>
      <p class="statistics-kpi-value">{metric.value}</p>
      <p class="statistics-kpi-detail">{metric.detail}</p>
    </article>
  {/each}
</section>

<style>
  .statistics-kpis {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: var(--ds-space-3);
  }
  .statistics-kpi {
    min-width: 0;
    padding: var(--ds-space-4);
    border: 1px solid var(--ds-color-border);
    border-top: 3px solid var(--ds-color-border);
    border-radius: var(--ds-radius-lg);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-sm);
  }
  .statistics-kpi-positive {
    border-top-color: var(--ds-color-positive);
  }
  .statistics-kpi-warning {
    border-top-color: var(--ds-color-warning);
  }
  .statistics-kpi-label,
  .statistics-kpi-value,
  .statistics-kpi-detail {
    margin: 0;
  }
  .statistics-kpi-label {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
    font-weight: 600;
  }
  .statistics-kpi-value {
    margin-top: var(--ds-space-2);
    color: var(--ds-color-text);
    font-size: 1.3rem;
    font-weight: 700;
    line-height: 1.1;
  }
  .statistics-kpi-detail {
    margin-top: var(--ds-space-2);
    color: var(--ds-color-text-muted);
    font-size: var(--ds-text-xs);
  }

  @media (max-width: 68em) {
    .statistics-kpis {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
  @media (max-width: 34em) {
    .statistics-kpis {
      grid-template-columns: 1fr;
    }
  }
</style>
