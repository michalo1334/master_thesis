<script lang="ts">
  import { Tabs } from "bits-ui";
  import type { SimulationReportDocument } from "./SimulationReportDocument.svelte";
  import Canvas from "../graph/canvas/Canvas.svelte";
  import KpiCards from "./KpiCards.svelte";
  import StatisticalChart from "./StatisticalChart.svelte";
  import {
    formatProbability,
    formatFeasibility,
    formatCapabilityFlows,
    formatCapabilitySupport,
    formatCapabilityStatusExplanation,
    formatSimulationReportKpis,
  } from "./simulation-report";
  import {
    actionSuccessOptions,
    cdfOptions,
    convergenceOptions,
    histogramOptions,
  } from "./chart-options";
  import { heatmapLegend } from "./heatmap";
  import HeatmapCanvas from "./HeatmapCanvas.svelte";
  import ReportProgress from "../ReportProgress.svelte";

  interface Props {
    document: SimulationReportDocument;
    onOpenSourceGraph?: () => Promise<boolean>;
  }

  type CapabilityStatus = {
    capability_id: string;
    operational: boolean;
    required_flow_count: number;
    missing_flow_count: number;
    supporting_host_count: number;
    min_operational_support: number;
  };

  type RequiredFlowStatus = {
    id: string;
    source: string;
    target: string;
    availability: "Available" | "Unavailable";
  };

  let { document, onOpenSourceGraph = undefined }: Props = $props();
  let activeTab = $state("report");
  let capabilityImpacts = $derived.by(() => {
    const report = document.reportData;
    if (!report) return [];

    const names = new Map(
      report.graph.nodes.flatMap((node) =>
        node.type === "MissionCapability" ? [[node.id, node.data.name]] : [],
      ),
    );

    return report.charts.capability_impact.map((impact) => ({
      ...impact,
      name: names.get(impact.capability_id) ?? impact.capability_id,
    }));
  });
  let capabilityStatuses = $derived.by(() => {
    const report = document.reportData;
    if (!report) return [];
    const nodes = new Map(report.graph.nodes.map((node) => [node.id, node]));
    const hostsBySegment = report.graph.edges.reduce<Record<string, string[]>>(
      (hosts, edge) => {
        if (edge.type === "Contains")
          (hosts[edge.from_id] ??= []).push(edge.to_id);
        return hosts;
      },
      {},
    );

    return report.capability_statuses.map((value) => {
      const status = value as CapabilityStatus;
      const capability = nodes.get(status.capability_id);
      const requiredFlows =
        capability?.type === "MissionCapability"
          ? capability.data.required_flows.map((flow, index) => {
              const source = nodes.get(flow.source_segment_id);
              const target = nodes.get(flow.target_service_id);
              const available = report.operational_flows.some(
                (operationalFlow) =>
                  operationalFlow.to_id === flow.target_service_id &&
                  (hostsBySegment[flow.source_segment_id] ?? []).includes(
                    operationalFlow.from_id,
                  ),
              );
              return {
                id: `${flow.source_segment_id}:${flow.target_service_id}:${index}`,
                source:
                  source?.type === "NetworkSegment"
                    ? source.data.name
                    : flow.source_segment_id,
                target:
                  target?.type === "Service"
                    ? `${target.data.name}:${target.data.port}`
                    : flow.target_service_id,
                availability: available ? "Available" : "Unavailable",
              } satisfies RequiredFlowStatus;
            })
          : [];

      return {
        capabilityId: status.capability_id,
        name:
          capability?.type === "MissionCapability"
            ? capability.data.name
            : status.capability_id,
        status: status.operational ? "Operational" : "Unavailable",
        flows: formatCapabilityFlows(
          status.required_flow_count,
          status.missing_flow_count,
        ),
        support: formatCapabilitySupport(
          status.supporting_host_count,
          status.min_operational_support,
        ),
        explanation: formatCapabilityStatusExplanation(
          status.required_flow_count,
          status.missing_flow_count,
          status.supporting_host_count,
          status.min_operational_support,
        ),
        requiredFlows,
      };
    });
  });
</script>

<article class="simulation-report" aria-labelledby="simulation-report-title">
  <header class="simulation-report-header">
    <div>
      <p class="simulation-report-eyebrow">Simulation result</p>
      <h1 id="simulation-report-title">{document.title}</h1>
    </div>
    {#if onOpenSourceGraph}
      <button
        class="simulation-report-open"
        type="button"
        onclick={() => void onOpenSourceGraph?.()}
      >
        Open source graph
      </button>
    {/if}
  </header>

  {#if document.status === "pending"}
    <section
      class="simulation-report-waiting"
      aria-label="Simulation pending"
      aria-live="polite"
    >
      <ReportProgress
        progress={document.progress}
        waitingMessage="Simulation requested, waiting for results..."
        label="runs completed"
      />
    </section>
  {:else if document.status === "loading"}
    <section class="simulation-report-waiting" aria-label="Loading report">
      <ReportProgress
        progress={null}
        waitingMessage="Loading report..."
        label="runs completed"
      />
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

        {#if capabilityImpacts.length > 0}
          <section
            class="simulation-report-section"
            aria-labelledby="capability-impact-title"
          >
            <h2 id="capability-impact-title">Mission capability disruption</h2>
            <table class="capability-impact-table">
              <caption>
                Probability that each mission capability is disrupted during a
                simulation run.
              </caption>
              <thead>
                <tr>
                  <th scope="col">Capability</th>
                  <th scope="col">Disruption probability</th>
                </tr>
              </thead>
              <tbody>
                {#each capabilityImpacts as impact (impact.capability_id)}
                  <tr>
                    <td>{impact.name}</td>
                    <td>{formatProbability(impact.down_probability)}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </section>
        {/if}

        <section
          class="simulation-report-section"
          aria-labelledby="scenario-feasibility-title"
        >
          <h2 id="scenario-feasibility-title">Starting scenario feasibility</h2>
          <p class="simulation-report-feasibility">
            {formatFeasibility(document.reportData.feasible)}
          </p>
        </section>

        {#if capabilityStatuses.length > 0}
          <section
            class="simulation-report-section"
            aria-labelledby="capability-status-title"
          >
            <h2 id="capability-status-title">Pre-attack capability status</h2>
            <div class="simulation-report-table-wrap">
              <table class="capability-impact-table capability-status-table">
                <caption>
                  Capability status before the simulated attack starts.
                </caption>
                <thead>
                  <tr>
                    <th scope="col">Capability</th>
                    <th scope="col">Status</th>
                    <th scope="col">Flows available / required</th>
                    <th scope="col">Required flows</th>
                    <th scope="col">Supports available / minimum</th>
                    <th scope="col">Explanation</th>
                  </tr>
                </thead>
                <tbody>
                  {#each capabilityStatuses as capability (capability.capabilityId)}
                    <tr>
                      <td>{capability.name}</td>
                      <td>{capability.status}</td>
                      <td>{capability.flows}</td>
                      <td>
                        {#if capability.requiredFlows.length > 0}
                          <ul
                            class="capability-required-flow-list"
                            aria-label={`Required flows for ${capability.name}`}
                          >
                            {#each capability.requiredFlows as flow (flow.id)}
                              <li>
                                {flow.source} to {flow.target}: {flow.availability}
                              </li>
                            {/each}
                          </ul>
                        {:else}
                          —
                        {/if}
                      </td>
                      <td>{capability.support}</td>
                      <td>{capability.explanation}</td>
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          </section>
        {/if}

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
              across simulation runs. Dashed lines show operational flows. Drag
              nodes to arrange this report view; positions are local and are not
              saved to the topology.
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
            <HeatmapCanvas {document} />
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
    padding: var(--ui-space-6);
    color: var(--ui-color-text);
    background: var(--ui-color-surface);
  }

  .simulation-report-header {
    display: flex;
    align-items: end;
    justify-content: space-between;
    gap: var(--ui-space-3);
    max-width: 62rem;
    margin-bottom: var(--ui-space-6);
  }

  .simulation-report-eyebrow {
    margin: 0;
    color: var(--ui-color-accent);
    font-size: var(--ui-text-xs);
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
    margin-top: var(--ui-space-1);
    font-size: 1.5rem;
    line-height: 1.2;
  }

  h2 {
    font-size: var(--ui-text-base);
    font-weight: 700;
    margin-bottom: var(--ui-space-3);
  }

  .simulation-report-open {
    flex: none;
    min-height: var(--ui-control-height);
    padding: 0 var(--ui-space-3);
    border: 1px solid var(--ui-color-accent);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-accent);
    color: var(--ui-color-paper);
    font: inherit;
    white-space: nowrap;
  }

  .simulation-report-empty,
  .simulation-report-waiting {
    display: grid;
    place-content: center;
    place-items: center;
    min-height: 16rem;
    border: 2px dashed var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    color: var(--ui-color-text-secondary);
    text-align: center;
    gap: var(--ui-space-3);
  }

  .simulation-report-empty p {
    max-width: 20rem;
    font-size: var(--ui-text-sm);
  }

  :global(.simulation-report-tabs) {
    flex: 1;
    display: grid;
    grid-template-columns: 8rem minmax(0, 1fr);
    grid-template-rows: minmax(0, 1fr);
    gap: var(--ui-space-5);
    align-items: start;
    min-height: 0;
  }

  :global(.simulation-report-tab-list) {
    position: sticky;
    top: 0;
    display: grid;
    gap: var(--ui-space-1);
    padding: var(--ui-space-1);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }

  :global(.simulation-report-tab) {
    min-height: 2.5rem;
    padding: 0 var(--ui-space-3);
    border: 0;
    border-left: 3px solid transparent;
    border-radius: var(--ui-radius-sm);
    background: transparent;
    color: var(--ui-color-text-secondary);
    font: inherit;
    text-align: left;
  }

  :global(.simulation-report-tab[data-state="active"]) {
    border-left-color: var(--ui-color-accent);
    background: var(--ui-color-accent-soft);
    color: var(--ui-color-accent);
    font-weight: 700;
  }

  :global(.simulation-report-tab-panel) {
    grid-column: 2;
    height: 100%;
    min-width: 0;
    min-height: 0;
  }

  .simulation-report-section {
    margin-top: var(--ui-space-8);
    max-width: 62rem;
  }

  .simulation-report-feasibility {
    padding: var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    font-size: var(--ui-text-sm);
    font-weight: 600;
  }

  .simulation-report-chart-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--ui-space-3);
  }

  .capability-impact-table {
    width: 100%;
    border-collapse: collapse;
    border: 1px solid var(--ui-color-border);
    background: var(--ui-color-paper);
    font-size: var(--ui-text-sm);
  }

  .capability-impact-table caption {
    padding: var(--ui-space-2) var(--ui-space-3);
    color: var(--ui-color-text-secondary);
    text-align: left;
  }

  .capability-impact-table th,
  .capability-impact-table td {
    padding: var(--ui-space-2) var(--ui-space-3);
    border-top: 1px solid var(--ui-color-border-soft);
    text-align: left;
  }

  .capability-impact-table th {
    color: var(--ui-color-text-secondary);
    font-weight: 600;
  }

  .capability-impact-table th:last-child,
  .capability-impact-table td:last-child {
    text-align: right;
  }

  .simulation-report-table-wrap {
    overflow-x: auto;
  }

  .capability-status-table {
    min-width: 68rem;
  }

  .capability-status-table th:last-child,
  .capability-status-table td:last-child {
    text-align: left;
  }

  .capability-required-flow-list {
    display: grid;
    gap: var(--ui-space-1);
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .simulation-report-heatmap {
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr);
    gap: var(--ui-space-4);
    height: 100%;
    min-width: 0;
    min-height: 0;
  }

  .simulation-report-heatmap-header {
    display: grid;
    gap: var(--ui-space-2);
    max-width: 48rem;
  }

  .simulation-report-heatmap-header p {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }

  .simulation-report-heatmap-legend {
    display: flex;
    flex-wrap: wrap;
    gap: var(--ui-space-2) var(--ui-space-4);
    margin: 0;
    padding: 0;
    list-style: none;
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }

  .simulation-report-heatmap-legend li {
    display: flex;
    align-items: center;
    gap: var(--ui-space-1);
  }

  .simulation-report-heatmap-legend span {
    width: 0.875rem;
    height: 0.875rem;
    border: 1px solid color-mix(in srgb, var(--ui-color-text) 25%, transparent);
    border-radius: 50%;
  }

  .simulation-report-heatmap-canvas {
    min-height: 0;
    overflow: hidden;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
  }

  @media (max-width: 68em) {
    .simulation-report-chart-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 48em) {
    .simulation-report {
      padding: var(--ui-space-4);
    }

    .simulation-report-header {
      align-items: start;
      flex-direction: column;
    }

    :global(.simulation-report-tabs) {
      grid-template-columns: minmax(0, 1fr);
      grid-template-rows: auto minmax(0, 1fr);
      gap: var(--ui-space-4);
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
      border-bottom-color: var(--ui-color-accent);
    }

    :global(.simulation-report-tab-panel) {
      grid-column: 1;
    }
  }
</style>
