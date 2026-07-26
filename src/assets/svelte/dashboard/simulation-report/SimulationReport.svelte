<script lang="ts">
  import type { SimulationReportDocument } from "./SimulationReportDocument.svelte";
  import KpiCards from "./KpiCards.svelte";
  import StatisticalChart from "./StatisticalChart.svelte";
  import { formatSimulationReportKpis } from "./simulation-report";
  import {
    actionSuccessOptions,
    cdfOptions,
    convergenceOptions,
    histogramOptions,
  } from "./chart-options";

  interface Props {
    document: SimulationReportDocument;
  }

  let { document }: Props = $props();
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
    <KpiCards
      metrics={formatSimulationReportKpis(
        document.reportData.summary,
        document.reportData.run_count,
      )}
    />

    <section
      class="simulation-report-section"
      aria-labelledby="distribution-title"
    >
      <h2 id="distribution-title">Blast-radius distribution</h2>
      <div class="simulation-report-chart-grid">
        <StatisticalChart
          id="blast-radius-histogram"
          title="Blast-radius histogram"
          takeaway="Shows how often each blast-radius range occurred."
          ariaLabel="Histogram of simulation runs by compromised-host range"
          option={histogramOptions(document.reportData.charts.histogram)}
        />
        <StatisticalChart
          id="blast-radius-cdf"
          title="Cumulative distribution"
          takeaway="Shows the chance that a run stays at or below each blast radius."
          ariaLabel="Cumulative probability by compromised-host count"
          option={cdfOptions(document.reportData.charts.cdf)}
        />
      </div>
    </section>

    <section
      class="simulation-report-section"
      aria-labelledby="convergence-title"
    >
      <h2 id="convergence-title">Monte Carlo convergence</h2>
      <div class="simulation-report-chart-grid">
        <StatisticalChart
          id="blast-radius-convergence"
          title="Running mean blast radius"
          takeaway="Shows whether the mean blast radius has stabilized across runs."
          ariaLabel="Running mean blast radius by simulation run"
          option={convergenceOptions(document.reportData.charts.convergence)}
        />
      </div>
    </section>

    {#if document.reportData.charts.action_success.length > 0}
      <section
        class="simulation-report-section"
        aria-labelledby="actions-title"
      >
        <h2 id="actions-title">Attack action statistics</h2>
        <div class="simulation-report-chart-grid">
          <StatisticalChart
            id="action-success"
            title="Action success"
            takeaway="Compares attempted actions with successful actions by type."
            ariaLabel="Attempts and successful actions by attack action type"
            option={actionSuccessOptions(
              document.reportData.charts.action_success,
            )}
          />
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
