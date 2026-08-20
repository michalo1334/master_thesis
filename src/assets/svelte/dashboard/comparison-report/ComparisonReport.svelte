<script lang="ts">
  import type { ComparisonReportDocument } from "./ComparisonReportDocument.svelte";
  import GraphDiff from "../graph/GraphDiff.svelte";
  import { formatRuntime } from "../format";
  import {
    comparisonMetrics,
    formatDelta,
    formatPercentagePointDelta,
    formatPercentDelta,
    formatStrategy,
  } from "./comparison-report";
  import {
    formatCapabilityFlows,
    formatCapabilitySupport,
    formatProbability,
  } from "../simulation-report/simulation-report";
  import ReportProgress from "../ReportProgress.svelte";

  interface Props {
    document: ComparisonReportDocument;
  }

  type CapabilityStatus = {
    capability_id: string;
    operational: boolean;
    required_flow_count: number;
    missing_flow_count: number;
    supporting_host_count: number;
    min_operational_support: number;
  };

  let { document }: Props = $props();
  let loadedReports = $derived(
    [
      document.baselineReport,
      document.optimizationReport,
      document.postOptimizationReport,
    ].filter((report) => report.status === "loaded").length,
  );
  let baseline = $derived(document.baselineReport.reportData);
  let postOptimization = $derived(document.postOptimizationReport.reportData);
  let optimization = $derived(document.optimizationReport.reportData);
  let metrics = $derived(
    baseline && postOptimization
      ? comparisonMetrics(baseline, postOptimization)
      : [],
  );
  let feasibility = $derived(
    postOptimization
      ? postOptimization.feasible
        ? "Feasible"
        : "Infeasible"
      : undefined,
  );
  let capabilityImpactComparison = $derived.by(() => {
    if (!baseline || !postOptimization) return [];
    const names = new Map(
      [...baseline.graph.nodes, ...postOptimization.graph.nodes].flatMap(
        (node) =>
          node.type === "MissionCapability" ? [[node.id, node.data.name]] : [],
      ),
    );
    const baselineImpacts = new Map(
      baseline.charts.capability_impact.map((impact) => [
        impact.capability_id,
        impact.down_probability,
      ]),
    );
    const defendedImpacts = new Map(
      postOptimization.charts.capability_impact.map((impact) => [
        impact.capability_id,
        impact.down_probability,
      ]),
    );

    return [
      ...new Set([...baselineImpacts.keys(), ...defendedImpacts.keys()]),
    ].map((capabilityId) => ({
      capabilityId,
      name: names.get(capabilityId) ?? capabilityId,
      baseline: baselineImpacts.get(capabilityId) ?? 0,
      defended: defendedImpacts.get(capabilityId) ?? 0,
    }));
  });
  let capabilityStatusComparison = $derived.by(() => {
    if (!baseline || !postOptimization) return [];
    const names = new Map(
      [...baseline.graph.nodes, ...postOptimization.graph.nodes].flatMap(
        (node) =>
          node.type === "MissionCapability" ? [[node.id, node.data.name]] : [],
      ),
    );
    const baselineStatuses = new Map(
      baseline.capability_statuses.map((value) => {
        const status = value as CapabilityStatus;
        return [status.capability_id, status] as const;
      }),
    );
    const defendedStatuses = new Map(
      postOptimization.capability_statuses.map((value) => {
        const status = value as CapabilityStatus;
        return [status.capability_id, status] as const;
      }),
    );
    return [
      ...new Set([...baselineStatuses.keys(), ...defendedStatuses.keys()]),
    ].map((capabilityId) => {
      const baselineStatus = baselineStatuses.get(capabilityId);
      const defendedStatus = defendedStatuses.get(capabilityId);
      return {
        capabilityId,
        name: names.get(capabilityId) ?? capabilityId,
        baseline: baselineStatus
          ? baselineStatus.operational
            ? "Operational"
            : "Unavailable"
          : "—",
        defended: defendedStatus
          ? defendedStatus.operational
            ? "Operational"
            : "Unavailable"
          : "—",
        baselineFlows: baselineStatus
          ? formatCapabilityFlows(
              baselineStatus.required_flow_count,
              baselineStatus.missing_flow_count,
            )
          : "—",
        defendedFlows: defendedStatus
          ? formatCapabilityFlows(
              defendedStatus.required_flow_count,
              defendedStatus.missing_flow_count,
            )
          : "—",
        baselineSupport: baselineStatus
          ? formatCapabilitySupport(
              baselineStatus.supporting_host_count,
              baselineStatus.min_operational_support,
            )
          : "—",
        defendedSupport: defendedStatus
          ? formatCapabilitySupport(
              defendedStatus.supporting_host_count,
              defendedStatus.min_operational_support,
            )
          : "—",
      };
    });
  });
</script>

<article class="comparison-report" aria-labelledby="comparison-report-title">
  <header>
    <p>Combined analysis</p>
    <h1 id="comparison-report-title">{document.title}</h1>
  </header>

  {#if document.baselineReport.status === "error" || document.postOptimizationReport.status === "error" || document.optimizationReport.status === "error"}
    <section class="comparison-report-status" aria-live="polite">
      <p>
        Unable to complete the comparison because one of its reports failed.
      </p>
    </section>
  {:else if !baseline || !postOptimization || !optimization}
    <section class="comparison-report-status" aria-live="polite">
      <ReportProgress
        progress={{ completed: loadedReports, total: 3 }}
        waitingMessage="Loading analysis reports..."
        label="reports loaded"
      />
    </section>
  {:else}
    <section aria-labelledby="comparison-metrics-title">
      <h2 id="comparison-metrics-title">Baseline and post-optimization</h2>
      <div class="comparison-report-table-wrap comparison-report-metric-table">
        <table>
          <thead>
            <tr>
              <th scope="col">Metric</th>
              <th scope="col">Baseline</th>
              <th scope="col">Post-optimization</th>
              <th scope="col">Absolute delta</th>
              <th scope="col">Percent delta</th>
            </tr>
          </thead>
          <tbody>
            {#each metrics as metric (metric.label)}
              {@const delta = metric.postOptimization - metric.baseline}
              <tr>
                <th scope="row">{metric.label}</th>
                <td>{metric.baseline}</td>
                <td>{metric.postOptimization}</td>
                <td>{formatDelta(delta)}</td>
                <td
                  >{formatPercentDelta(
                    metric.baseline,
                    metric.postOptimization,
                  )}</td
                >
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
      <ul
        class="comparison-report-metric-cards"
        aria-label="Comparison metrics"
      >
        {#each metrics as metric (metric.label)}
          {@const delta = metric.postOptimization - metric.baseline}
          <li>
            <h3>{metric.label}</h3>
            <dl>
              <div>
                <dt>Baseline</dt>
                <dd>{metric.baseline}</dd>
              </div>
              <div>
                <dt>Post-optimization</dt>
                <dd>{metric.postOptimization}</dd>
              </div>
              <div>
                <dt>Absolute delta</dt>
                <dd>{formatDelta(delta)}</dd>
              </div>
              <div>
                <dt>Percent delta</dt>
                <dd>
                  {formatPercentDelta(metric.baseline, metric.postOptimization)}
                </dd>
              </div>
            </dl>
          </li>
        {/each}
      </ul>
    </section>

    <section aria-labelledby="optimization-summary-title">
      <h2 id="optimization-summary-title">Optimization</h2>
      <dl class="comparison-report-summary">
        <div>
          <dt>Strategy</dt>
          <dd>{formatStrategy(optimization.strategy)}</dd>
        </div>
        {#if feasibility}
          <div>
            <dt>Pre-attack feasibility</dt>
            <dd>{feasibility}</dd>
          </div>
        {/if}
        <div>
          <dt>Budget</dt>
          <dd>
            {optimization.requested_budget} requested / {optimization.used_budget}
            used
          </dd>
        </div>
        <div>
          <dt>Runtime</dt>
          <dd>{formatRuntime(optimization.runtime_ms)}</dd>
        </div>
      </dl>
      {#if optimization.actions.length > 0}
        <ul class="comparison-report-actions">
          {#each optimization.actions as action (action.id)}
            <li>{action.label} <span>{action.kind}</span></li>
          {/each}
        </ul>
      {:else}
        <p class="comparison-report-empty">No defenses were selected.</p>
      {/if}
    </section>

    {#if capabilityImpactComparison.length > 0}
      <section aria-labelledby="capability-impact-comparison-title">
        <h2 id="capability-impact-comparison-title">
          Mission capability disruption probability
        </h2>
        <div class="comparison-report-table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Capability</th>
                <th scope="col">Baseline</th>
                <th scope="col">Defended</th>
                <th scope="col">Delta</th>
              </tr>
            </thead>
            <tbody>
              {#each capabilityImpactComparison as capability (capability.capabilityId)}
                <tr>
                  <th scope="row">{capability.name}</th>
                  <td>{formatProbability(capability.baseline)}</td>
                  <td>{formatProbability(capability.defended)}</td>
                  <td>
                    {formatPercentagePointDelta(
                      capability.baseline,
                      capability.defended,
                    )}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </section>
    {/if}

    {#if capabilityStatusComparison.length > 0}
      <section aria-labelledby="capability-status-comparison-title">
        <h2 id="capability-status-comparison-title">
          Mission capability status
        </h2>
        <div class="comparison-report-table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Capability</th>
                <th scope="col">Baseline</th>
                <th scope="col">Defended</th>
                <th scope="col">Baseline flows</th>
                <th scope="col">Defended flows</th>
                <th scope="col">Baseline supports</th>
                <th scope="col">Defended supports</th>
              </tr>
            </thead>
            <tbody>
              {#each capabilityStatusComparison as capability (capability.capabilityId)}
                <tr>
                  <th scope="row">{capability.name}</th>
                  <td>{capability.baseline}</td>
                  <td>{capability.defended}</td>
                  <td>{capability.baselineFlows}</td>
                  <td>{capability.defendedFlows}</td>
                  <td>{capability.baselineSupport}</td>
                  <td>{capability.defendedSupport}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </section>
    {/if}

    <section
      class="comparison-report-diff"
      aria-labelledby="comparison-diff-title"
    >
      <div>
        <h2 id="comparison-diff-title">Structural graph diff</h2>
        <p>Changes made by the selected defenses.</p>
      </div>
      {#if document.optimizationReport.graphDiff}
        <div class="comparison-report-diff-canvas">
          <GraphDiff document={document.optimizationReport.graphDiff} />
        </div>
      {:else if document.optimizationReport.graphDiffStatus === "error"}
        <button type="button" onclick={() => void document.loadGraphDiff()}
          >Retry graph diff</button
        >
      {:else}
        <p class="comparison-report-empty">Loading graph diff...</p>
      {/if}
    </section>
  {/if}
</article>

<style>
  .comparison-report {
    height: 100%;
    min-height: 0;
    overflow: auto;
    overscroll-behavior: contain;
    padding: var(--ui-space-6);
    scroll-padding-block-start: var(--ui-document-tabs-height);
    background: var(--ui-color-surface);
    color: var(--ui-color-text);
  }
  header p,
  h1,
  h2,
  p,
  dl {
    margin: 0;
  }
  header p {
    color: var(--ui-color-accent);
    font-size: var(--ui-text-xs);
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  h1 {
    margin-top: var(--ui-space-1);
    font-size: 1.5rem;
  }
  section {
    max-width: 70rem;
    margin-top: var(--ui-space-7);
    scroll-margin-block-start: var(--ui-document-tabs-height);
  }
  h2 {
    margin-bottom: var(--ui-space-3);
    font-size: var(--ui-text-base);
  }
  .comparison-report-table-wrap {
    overflow-x: auto;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }
  table {
    width: 100%;
    border-collapse: collapse;
    text-align: left;
    font-size: var(--ui-text-sm);
  }
  th,
  td {
    padding: var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border);
    white-space: nowrap;
  }
  thead th {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    text-transform: uppercase;
  }
  tbody tr:last-child > * {
    border-bottom: 0;
  }
  .comparison-report-metric-cards {
    display: none;
  }
  .comparison-report-summary {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
    gap: var(--ui-space-3);
  }
  .comparison-report-summary div {
    padding: var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }
  dt {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    text-transform: uppercase;
  }
  dd {
    margin: var(--ui-space-1) 0 0;
  }
  .comparison-report-actions {
    display: grid;
    gap: var(--ui-space-1);
    margin: var(--ui-space-3) 0 0;
    padding-left: 1.25rem;
    font-size: var(--ui-text-sm);
  }
  .comparison-report-actions span {
    color: var(--ui-color-text-secondary);
  }
  .comparison-report-diff {
    display: grid;
    grid-template-rows: auto minmax(22rem, 36rem);
    gap: var(--ui-space-3);
    min-width: 0;
  }
  .comparison-report-diff p,
  .comparison-report-empty {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }
  .comparison-report-diff-canvas {
    min-width: 0;
    min-height: 0;
    overflow: hidden;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
  }
  .comparison-report-status {
    min-height: 16rem;
    display: grid;
    place-content: center;
    justify-items: center;
    gap: var(--ui-space-3);
    border: 2px dashed var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    color: var(--ui-color-text-secondary);
  }
  button {
    min-height: var(--ui-control-height);
    padding: 0 var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    color: inherit;
    font: inherit;
  }
  @media (max-width: 48em) {
    .comparison-report {
      padding: var(--ui-space-4);
    }
    .comparison-report-metric-table {
      display: none;
    }
    .comparison-report-metric-cards {
      display: grid;
      gap: var(--ui-space-3);
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .comparison-report-metric-cards li {
      padding: var(--ui-space-3);
      border: 1px solid var(--ui-color-border);
      border-radius: var(--ui-radius-md);
      background: var(--ui-color-paper);
    }
    .comparison-report-metric-cards h3 {
      margin: 0 0 var(--ui-space-3);
      font-size: var(--ui-text-sm);
    }
    .comparison-report-metric-cards dl {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: var(--ui-space-3);
    }
    .comparison-report-metric-cards dt {
      color: var(--ui-color-text-secondary);
      font-size: var(--ui-text-xs);
      text-transform: uppercase;
    }
    .comparison-report-metric-cards dd {
      margin: var(--ui-space-1) 0 0;
      overflow-wrap: anywhere;
    }
    .comparison-report-diff {
      grid-template-rows: auto minmax(18rem, 50dvh);
    }
  }
</style>
