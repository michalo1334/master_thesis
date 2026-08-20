<script lang="ts">
  import type { AnalysisReportDocument } from "./AnalysisReportDocument.svelte";
  import ReportProgress from "../ReportProgress.svelte";

  interface Props {
    document: AnalysisReportDocument;
  }

  let { document }: Props = $props();

  let statusLabel = $derived.by(() => {
    switch (document.reportData?.status ?? document.status) {
      case "completed":
        return "Completed";
      case "failed":
        return "Failed";
      case "running":
        return "Running";
      default:
        return "Pending";
    }
  });
</script>

<article class="analysis-report" aria-labelledby="analysis-report-title">
  <header class="analysis-report-header">
    <div>
      <p class="analysis-report-eyebrow">Evaluation analysis</p>
      <h1 id="analysis-report-title">{document.title}</h1>
    </div>
  </header>

  {#if document.status === "pending"}
    <section class="analysis-report-status" aria-live="polite">
      <ReportProgress
        progress={document.progress}
        waitingMessage="Evaluation running, waiting for results..."
        label="evaluation steps completed"
      />
    </section>
  {:else if document.status === "loading"}
    <section class="analysis-report-status" aria-live="polite">
      <ReportProgress
        progress={null}
        waitingMessage="Loading analysis report..."
        label="evaluation steps completed"
      />
    </section>
  {:else if document.status === "error"}
    <section class="analysis-report-status" aria-live="polite">
      <p>{document.errorReason || "Failed to load the analysis report."}</p>
    </section>
  {:else if document.status === "loaded" && document.reportData}
    <section class="analysis-report-section" aria-labelledby="summary-title">
      <h2 id="summary-title">Summary</h2>
      <dl class="analysis-report-summary">
        <div>
          <dt>Status</dt>
          <dd>{statusLabel}</dd>
        </div>
        <div>
          <dt>Manifest</dt>
          <dd>{document.reportData.manifest_title}</dd>
        </div>
        <div>
          <dt>Source graph</dt>
          <dd>{document.reportData.source_graph_title}</dd>
        </div>
        {#if document.reportData.failure_reason}
          <div>
            <dt>Failure reason</dt>
            <dd>{document.reportData.failure_reason}</dd>
          </div>
        {/if}
      </dl>
    </section>

    <section class="analysis-report-section" aria-labelledby="plans-title">
      <h2 id="plans-title">Plans</h2>
      <div class="analysis-report-table-wrap">
        <table class="analysis-report-table">
          <thead>
            <tr>
              <th scope="col">Strategy</th>
              <th scope="col">Budget</th>
              <th scope="col">Selection seed</th>
              <th scope="col">Used budget</th>
              <th scope="col">Actions</th>
              <th scope="col">Status</th>
            </tr>
          </thead>
          <tbody>
            {#each document.reportData.plans as plan (plan.id)}
              <tr>
                <th scope="row">{plan.strategy}</th>
                <td>{plan.requested_budget}</td>
                <td>{plan.selection_seed}</td>
                <td>{plan.used_budget}</td>
                <td>{plan.action_count}</td>
                <td>{plan.status}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </section>

    <section
      class="analysis-report-section"
      aria-labelledby="experiments-title"
    >
      <h2 id="experiments-title">Aggregate results</h2>
      <div class="analysis-report-table-wrap">
        <table class="analysis-report-table">
          <thead>
            <tr>
              <th scope="col">Experiment</th>
              <th scope="col">Plan</th>
              <th scope="col">Trials</th>
              <th scope="col">Expected blast radius</th>
              <th scope="col">Median</th>
              <th scope="col">P95</th>
              <th scope="col">P99</th>
              <th scope="col">Min</th>
              <th scope="col">Max</th>
            </tr>
          </thead>
          <tbody>
            {#each document.reportData.experiments as experiment (experiment.id)}
              <tr>
                <th scope="row">{experiment.id.slice(0, 8)}</th>
                <td
                  >{experiment.optimization_run_id?.slice(0, 8) ??
                    "baseline"}</td
                >
                <td>{experiment.trial_count}</td>
                <td>{experiment.expected_blast_radius.toFixed(2)}</td>
                <td>{experiment.median_blast_radius}</td>
                <td>{experiment.blast_radius_p95}</td>
                <td>{experiment.blast_radius_p99}</td>
                <td>{experiment.min_blast_radius}</td>
                <td>{experiment.max_blast_radius}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </section>
  {/if}
</article>

<style>
  .analysis-report {
    height: 100%;
    min-height: 0;
    overflow: auto;
    overscroll-behavior: contain;
    padding: var(--ui-space-6);
    background: var(--ui-color-surface);
    color: var(--ui-color-text);
  }

  .analysis-report-header {
    max-width: 62rem;
    margin-bottom: var(--ui-space-6);
  }

  .analysis-report-eyebrow {
    margin: 0;
    color: var(--ui-color-accent);
    font-size: var(--ui-text-xs);
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  h1,
  h2,
  p,
  dl {
    margin: 0;
  }

  h1 {
    margin-top: var(--ui-space-1);
    font-size: 1.5rem;
    line-height: 1.2;
  }

  h2 {
    margin-bottom: var(--ui-space-3);
    font-size: var(--ui-text-base);
  }

  .analysis-report-status {
    min-height: 16rem;
    display: grid;
    place-content: center;
    justify-items: center;
    gap: var(--ui-space-3);
    border: 2px dashed var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    color: var(--ui-color-text-secondary);
  }

  .analysis-report-section {
    max-width: 70rem;
    margin-top: var(--ui-space-7);
  }

  .analysis-report-summary {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
    gap: var(--ui-space-3);
  }

  .analysis-report-summary div {
    padding: var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }

  .analysis-report-summary dt {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    text-transform: uppercase;
  }

  .analysis-report-summary dd {
    margin: var(--ui-space-1) 0 0;
  }

  .analysis-report-table-wrap {
    overflow-x: auto;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }

  .analysis-report-table {
    width: 100%;
    border-collapse: collapse;
    text-align: left;
    font-size: var(--ui-text-sm);
  }

  .analysis-report-table th,
  .analysis-report-table td {
    padding: var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border);
    white-space: nowrap;
  }

  .analysis-report-table thead th {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    text-transform: uppercase;
  }

  .analysis-report-table tbody tr:last-child > * {
    border-bottom: 0;
  }

  @media (max-width: 48em) {
    .analysis-report {
      padding: var(--ui-space-4);
    }
  }
</style>
