<script lang="ts">
  import KpiCards from "./KpiCards.svelte";
  import StatisticalChart from "./StatisticalChart.svelte";
  import {
    convergenceCharts,
    distributionCharts,
    sensitivityCharts,
    simulationKpis,
    strategyCharts,
  } from "./fixtures";
  import type { ChartSpec } from "./types";

  interface Props {
    title: string;
  }

  let { title }: Props = $props();

  const sections: readonly {
    id: string;
    title: string;
    description: string;
    charts: readonly ChartSpec[];
    layout: "three" | "one" | "mixed";
  }[] = [
    {
      id: "distribution",
      title: "Blast-radius distribution",
      description:
        "Outcome shape and critical-asset exposure across the completed simulation runs.",
      charts: distributionCharts,
      layout: "three",
    },
    {
      id: "convergence",
      title: "Convergence",
      description: "Estimate stability as the Monte Carlo sample grows.",
      charts: convergenceCharts,
      layout: "one",
    },
    {
      id: "strategy",
      title: "Strategy comparison",
      description:
        "Expected impact and use of the fixed defense budget by prioritization approach.",
      charts: strategyCharts,
      layout: "three",
    },
    {
      id: "sensitivity",
      title: "Sensitivity analysis",
      description:
        "How exposure, topology, and run count change outcome variability and confidence.",
      charts: sensitivityCharts,
      layout: "three",
    },
  ];
</script>

<article class="simulation-report" aria-labelledby="simulation-report-title">
  <header class="simulation-report-header">
    <p class="simulation-report-eyebrow">Simulation result</p>
    <h1 id="simulation-report-title">{title}</h1>
    <p>
      Deterministic analytical fixture for a 10,000-run attack-propagation
      simulation. Results are illustrative and do not alter simulation
      contracts.
    </p>
  </header>

  <section
    class="simulation-report-kpi-section"
    aria-labelledby="simulation-kpis-title"
  >
    <div class="simulation-report-section-heading">
      <h2 id="simulation-kpis-title">Key findings</h2>
      <p>
        Summary measures from the completed run set and the evaluated hybrid
        defense plan.
      </p>
    </div>
    <KpiCards metrics={simulationKpis} />
  </section>

  {#each sections as section (section.id)}
    <section aria-labelledby={`${section.id}-title`}>
      <div class="simulation-report-section-heading">
        <h2 id={`${section.id}-title`}>{section.title}</h2>
        <p>{section.description}</p>
      </div>
      <div
        class={[
          "simulation-report-chart-grid",
          `simulation-report-chart-grid-${section.layout}`,
        ]}
      >
        {#each section.charts as chart (chart.id)}
          <StatisticalChart {chart} />
        {/each}
      </div>
    </section>
  {/each}
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
  .simulation-report-header > p:last-child {
    margin-top: var(--ds-space-2);
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-base);
  }
  section + section {
    margin-top: var(--ds-space-8);
  }
  .simulation-report-section-heading {
    margin-bottom: var(--ds-space-3);
  }
  h2 {
    font-size: 1rem;
    line-height: 1.25;
  }
  .simulation-report-section-heading p {
    margin-top: var(--ds-space-1);
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
  }
  .simulation-report-chart-grid {
    display: grid;
    gap: var(--ds-space-3);
  }
  .simulation-report-chart-grid-three {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
  .simulation-report-chart-grid-one {
    grid-template-columns: minmax(0, 1fr);
  }
  .simulation-report-chart-grid-one :global(.statistical-chart) {
    max-width: 62rem;
  }

  @media (max-width: 78em) {
    .simulation-report-chart-grid-three {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
  @media (max-width: 48em) {
    .simulation-report {
      padding: var(--ds-space-4);
    }
    .simulation-report-chart-grid-three {
      grid-template-columns: 1fr;
    }
  }
</style>
