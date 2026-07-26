<script lang="ts">
  import { Tabs } from "bits-ui";
  import type { SimulationReportDocument } from "./SimulationReportDocument.svelte";
  import Canvas from "../graph/canvas/Canvas.svelte";
  import KpiCards from "./KpiCards.svelte";
  import StatisticalChart from "./StatisticalChart.svelte";
  import { formatSimulationReportKpis } from "./simulation-report";
  import {
    actionSuccessOptions,
    cdfOptions,
    convergenceOptions,
    histogramOptions,
  } from "./chart-options";
  import { heatmapLegend, simulationHeatmapAppearance } from "./heatmap";

  interface Props {
    document: SimulationReportDocument;
  }

  let { document }: Props = $props();
  let activeTab = $state("report");
  let heatmapAppearance = $derived(
    document.reportData
      ? simulationHeatmapAppearance(document.reportData.charts)
      : undefined,
  );
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
  {:else if document.status === "loaded" && document.reportData && document.heatmapGraph}
    <Tabs.Root
      class="simulation-report-tabs"
      orientation="vertical"
      value={activeTab}
      onValueChange={(value) => (activeTab = value)}
    >
      <Tabs.List class="simulation-report-tab-list" aria-label="Report views">
        <Tabs.Trigger class="simulation-report-tab" value="report"
          >Report</Tabs.Trigger
        >
        <Tabs.Trigger class="simulation-report-tab" value="heatmap"
          >Heatmap</Tabs.Trigger
        >
      </Tabs.List>

      <Tabs.Content class="simulation-report-tab-panel" value="report">
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
              option={convergenceOptions(
                document.reportData.charts.convergence,
              )}
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
      </Tabs.Content>

      <Tabs.Content class="simulation-report-tab-panel" value="heatmap">
        <section
          class="simulation-report-heatmap"
          aria-labelledby="heatmap-title"
        >
          <div class="simulation-report-heatmap-header">
            <h2 id="heatmap-title">Attack-path heatmap</h2>
            <p id="heatmap-description">
              Host cards and traversed edges are colored by their probability
              across simulation runs. Drag nodes to arrange this report view;
              positions are local and are not saved to the topology.
            </p>
          </div>
          <ul
            class="simulation-report-heatmap-legend"
            aria-label="Heatmap probability legend"
          >
            {#each heatmapLegend as item (item.label)}
              <li>
                <span style:background-color={item.color} aria-hidden="true"
                ></span>{item.label}
              </li>
            {/each}
          </ul>
          <div
            class="simulation-report-heatmap-canvas"
            aria-describedby="heatmap-description"
          >
            <Canvas
              graph={document.heatmapGraph}
              nodeAppearance={heatmapAppearance?.nodeAppearance}
              edgeAppearance={heatmapAppearance?.edgeAppearance}
              selectedNodeId={document.heatmapSelectedNodeId}
              selectedEdgeId={document.heatmapSelectedEdgeId}
              onGraphChange={(graph) => (document.heatmapGraph = graph)}
              onSelectNode={(nodeId) => document.selectHeatmapNode(nodeId)}
              onSelectEdge={(edgeId) => document.selectHeatmapEdge(edgeId)}
              onClearSelection={() => document.clearHeatmapSelection()}
              ariaLabel="Simulation attack-path heatmap"
            />
          </div>
        </section>
      </Tabs.Content>
    </Tabs.Root>
  {/if}
</article>

<style>
  .simulation-report {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
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

  :global(.simulation-report-tabs) {
    flex: 1;
    display: grid;
    grid-template-columns: 8rem minmax(0, 1fr);
    grid-template-rows: minmax(0, 1fr);
    gap: var(--ds-space-5);
    align-items: start;
    min-height: 0;
  }

  :global(.simulation-report-tab-list) {
    position: sticky;
    top: 0;
    display: grid;
    gap: var(--ds-space-1);
    padding: var(--ds-space-1);
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
  }

  :global(.simulation-report-tab) {
    min-height: 2.5rem;
    padding: 0 var(--ds-space-3);
    border: 0;
    border-left: 3px solid transparent;
    border-radius: var(--ds-radius-sm);
    background: transparent;
    color: var(--ds-color-text-secondary);
    font: inherit;
    text-align: left;
  }

  :global(.simulation-report-tab[data-state="active"]) {
    border-left-color: var(--ds-color-accent);
    background: var(--ds-color-accent-soft);
    color: var(--ds-color-accent);
    font-weight: 700;
  }

  :global(.simulation-report-tab-panel) {
    grid-column: 2;
    height: 100%;
    min-width: 0;
    min-height: 0;
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

  .simulation-report-heatmap {
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr);
    gap: var(--ds-space-4);
    height: 100%;
    min-width: 0;
    min-height: 0;
  }

  .simulation-report-heatmap-header {
    display: grid;
    gap: var(--ds-space-2);
    max-width: 48rem;
  }

  .simulation-report-heatmap-header p {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
  }

  .simulation-report-heatmap-legend {
    display: flex;
    flex-wrap: wrap;
    gap: var(--ds-space-2) var(--ds-space-4);
    margin: 0;
    padding: 0;
    list-style: none;
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
  }

  .simulation-report-heatmap-legend li {
    display: flex;
    align-items: center;
    gap: var(--ds-space-1);
  }

  .simulation-report-heatmap-legend span {
    width: 0.875rem;
    height: 0.875rem;
    border: 1px solid color-mix(in srgb, var(--ds-color-text) 25%, transparent);
    border-radius: 50%;
  }

  .simulation-report-heatmap-canvas {
    min-height: 0;
    overflow: hidden;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
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

    :global(.simulation-report-tabs) {
      grid-template-columns: minmax(0, 1fr);
      grid-template-rows: auto minmax(0, 1fr);
      gap: var(--ds-space-4);
    }

    :global(.simulation-report-tab-list) {
      position: static;
      display: flex;
      padding: 0;
      overflow: hidden;
    }

    :global(.simulation-report-tab) {
      flex: 1;
      border-bottom: 3px solid transparent;
      border-left: 0;
      text-align: center;
    }

    :global(.simulation-report-tab[data-state="active"]) {
      border-bottom-color: var(--ds-color-accent);
    }

    :global(.simulation-report-tab-panel) {
      grid-column: 1;
    }
  }
</style>
