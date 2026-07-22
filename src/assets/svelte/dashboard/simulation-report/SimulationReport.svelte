<script lang="ts">
  import type { SimulationReportDocument } from "./SimulationReportDocument.svelte";
  import KpiCards from "./KpiCards.svelte";
  import StatisticalChart from "./StatisticalChart.svelte";
  import type { KpiMetric, ChartSpec } from "../contract";

  interface Props {
    document: SimulationReportDocument;
  }

  let { document }: Props = $props();

  const distributionCharts = $derived(
    document.reportData?.charts?.blast_radius_distribution ?? [],
  );
  const convergenceCharts = $derived(
    document.reportData?.charts?.convergence ?? [],
  );
  const actionCharts = $derived(
    document.reportData?.charts?.action_stats ?? [],
  );
  const kpis = $derived(document.reportData?.kpis ?? []);
</script>

<article class="simulation-report" aria-labelledby="simulation-report-title">
  <header class="simulation-report-header">
    <p class="simulation-report-eyebrow">Simulation result</p>
    <h1 id="simulation-report-title">{document.title}</h1>
  </header>

  {#if document.status === "pending"}
    <section class="simulation-report-waiting" aria-label="Simulation pending">
      <div class="simulation-report-spinner" aria-hidden="true"></div>
      <p>Simulation requested, waiting for results...</p>
    </section>
  {:else if document.status === "loading"}
    <section class="simulation-report-waiting" aria-label="Loading report">
      <div class="simulation-report-spinner" aria-hidden="true"></div>
      <p>Loading report...</p>
    </section>
  {:else if document.status === "error"}
    <section class="simulation-report-empty" aria-label="Report error">
      <p>
        {document.errorReason || "Failed to load simulation report."}
      </p>
    </section>
  {:else if document.status === "ready" && !document.reportData}
    <section class="simulation-report-empty" aria-label="No results yet">
      <p>
        No simulation results available. Run a simulation to populate this
        report.
      </p>
    </section>
  {:else if document.status === "loaded" && document.reportData}
    <KpiCards metrics={kpis} />

    {#if distributionCharts.length > 0}
      <section
        class="simulation-report-section"
        aria-label="Distribution charts"
      >
        <h2>Blast-radius distribution</h2>
        <div class="simulation-report-chart-grid">
          {#each distributionCharts as chart (chart.id)}
            <StatisticalChart {chart} />
          {/each}
        </div>
      </section>
    {/if}

    {#if convergenceCharts.length > 0}
      <section
        class="simulation-report-section"
        aria-label="Convergence charts"
      >
        <h2>Monte Carlo convergence</h2>
        <div class="simulation-report-chart-grid">
          {#each convergenceCharts as chart (chart.id)}
            <StatisticalChart {chart} />
          {/each}
        </div>
      </section>
    {/if}

    {#if actionCharts.length > 0}
      <section class="simulation-report-section" aria-label="Action statistics">
        <h2>Attack action statistics</h2>
        <div class="simulation-report-chart-grid">
          {#each actionCharts as chart (chart.id)}
            <StatisticalChart {chart} />
          {/each}
        </div>
      </section>
    {/if}
  {/if}
</article>

<style>
  .simulation-report {
    height: 100%;
    overflow: auto;
    padding: var(--ds-space-6);
    color: var(--ds-color-text);
    background: var(--ds-color-surface);
  }

  .simulation-report-header {
    max-width: 62rem;
    margin-bottom: var(--ds-space-6);
  }

  .simulation-report-eyebrow {
    margin: 0;
    color: var(--ds-color-accent);
    font-size: var(--ds-text-xs);
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  h1,
  h2,
  p {
    margin: 0;
  }

  h1 {
    margin-top: var(--ds-space-1);
    font-size: 1.5rem;
    line-height: 1.2;
  }

  h2 {
    font-size: var(--ds-text-base);
    font-weight: 700;
    margin-bottom: var(--ds-space-3);
  }

  .simulation-report-empty,
  .simulation-report-waiting {
    display: grid;
    place-content: center;
    place-items: center;
    min-height: 16rem;
    border: 2px dashed var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    color: var(--ds-color-text-secondary);
    text-align: center;
    gap: var(--ds-space-3);
  }

  .simulation-report-empty p,
  .simulation-report-waiting p {
    max-width: 20rem;
    font-size: var(--ds-text-sm);
  }

  .simulation-report-spinner {
    width: 2rem;
    height: 2rem;
    border: 3px solid var(--ds-color-border);
    border-top-color: var(--ds-color-accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  .simulation-report-section {
    margin-top: var(--ds-space-8);
    max-width: 62rem;
  }

  .simulation-report-chart-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--ds-space-3);
  }

  @media (max-width: 68em) {
    .simulation-report-chart-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 48em) {
    .simulation-report {
      padding: var(--ds-space-4);
    }
  }
</style>
