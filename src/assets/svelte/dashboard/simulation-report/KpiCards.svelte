<script module lang="ts">
  export interface KpiMetric {
    label: string;
    value: string;
    detail: string;
    tone: "neutral" | "positive" | "warning";
  }
</script>

<script lang="ts">
  interface Props {
    metrics: readonly KpiMetric[];
  }

  let { metrics }: Props = $props();
</script>

<section class="statistics-kpis" aria-label="Key performance indicators">
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
    gap: var(--ui-space-3);
  }
  .statistics-kpi {
    min-width: 0;
    padding: var(--ui-space-4);
    border: 1px solid var(--ui-color-border);
    border-top: 3px solid var(--ui-color-border);
    border-radius: var(--ui-radius-lg);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-sm);
  }
  .statistics-kpi-positive {
    border-top-color: var(--ui-color-positive);
  }
  .statistics-kpi-warning {
    border-top-color: var(--ui-color-warning);
  }
  .statistics-kpi-label,
  .statistics-kpi-value,
  .statistics-kpi-detail {
    margin: 0;
  }
  .statistics-kpi-label {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
    font-weight: 600;
  }
  .statistics-kpi-value {
    margin-top: var(--ui-space-2);
    color: var(--ui-color-text);
    font-size: 1.3rem;
    font-weight: 700;
    line-height: 1.1;
  }
  .statistics-kpi-detail {
    margin-top: var(--ui-space-2);
    color: var(--ui-color-text-muted);
    font-size: var(--ui-text-xs);
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
