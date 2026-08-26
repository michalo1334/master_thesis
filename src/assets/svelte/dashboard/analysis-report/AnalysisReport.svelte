<script lang="ts">
  import { Tabs } from "bits-ui";
  import type { AnalysisReportDocument } from "./AnalysisReportDocument.svelte";
  import type { DashboardApi } from "../dashboard-api";
  import ReportProgress from "../ReportProgress.svelte";
  import KpiCards, { type KpiMetric } from "../KpiCards.svelte";
  import type {
    EvaluationAnalysis,
    EvaluationAnalysisMetadata,
  } from "../../contracts.generated";

  interface Props {
    document: AnalysisReportDocument;
    api?: DashboardApi;
    onCancel?: () => Promise<boolean>;
  }

  let { document, api, onCancel = undefined }: Props = $props();
  let activeTab = $state("report");

  const formatNumber = (value: number | null | undefined): string =>
    value == null || !Number.isFinite(value) ? "—" : value.toFixed(3);
  const formatValue = (value: unknown): string =>
    value == null
      ? "—"
      : typeof value === "number"
        ? formatNumber(value)
        : String(value);

  const formatMetadataValue = (value: unknown): string => {
    if (value == null) return "—";
    if (typeof value === "object") return JSON.stringify(value, null, 2);
    return formatValue(value);
  };

  const metadataEntries = (value: unknown): [string, unknown][] =>
    value && typeof value === "object" && !Array.isArray(value)
      ? Object.entries(value)
      : [];

  const metadataKpis = (metadata: EvaluationAnalysisMetadata): KpiMetric[] => [
    {
      label: "Mode",
      value: metadata.command_mode,
      detail: "Analysis command",
      tone: "neutral",
    },
    {
      label: "Model",
      value: metadata.model_version,
      detail: "Statistical model",
      tone: "neutral",
    },
    {
      label: "Input trials",
      value: formatValue(metadata.input_trial_count),
      detail: "Trials in the input data",
      tone: "neutral",
    },
    {
      label: "Declared plan trials",
      value: formatValue(metadata.declared_plan_trial_count),
      detail: "Trials declared by the plan",
      tone: "neutral",
    },
    {
      label: "Runtime",
      value: formatNumber(metadata.analysis_runtime_seconds),
      detail: "Analysis runtime in seconds",
      tone: "neutral",
    },
    {
      label: "Simulator uncertainty",
      value:
        metadata.simulator_only_uncertainty == null
          ? "—"
          : metadata.simulator_only_uncertainty
            ? "Yes"
            : "No",
      detail: "Intervals describe simulator uncertainty",
      tone: "neutral",
    },
    {
      label: "Schema version",
      value: String(metadata.schema_version),
      detail: "Analysis result schema",
      tone: "neutral",
    },
    {
      label: "Package version",
      value: formatValue(metadata.package_version),
      detail: "Analysis package",
      tone: "neutral",
    },
    {
      label: "Pilot all pass",
      value:
        metadata.pilot_all_pass == null
          ? "—"
          : metadata.pilot_all_pass
            ? "Yes"
            : "No",
      detail: "Pilot checks",
      tone:
        metadata.pilot_all_pass == null
          ? "neutral"
          : metadata.pilot_all_pass
            ? "positive"
            : "warning",
    },
  ];

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

  function canOpenPlan(plan: { status: string }): boolean {
    return plan.status === "completed" || plan.status === "failed";
  }

  function canOpenExperiment(experiment: {
    optimization_run_id?: string | null;
  }): boolean {
    if (!experiment.optimization_run_id) {
      return document.reportData?.status !== "running";
    }
    const linked = document.reportData?.plans.find(
      (p) => p.id === experiment.optimization_run_id,
    );
    return linked
      ? canOpenPlan(linked)
      : document.reportData?.status !== "running";
  }

  function capabilityName(
    row: EvaluationAnalysis["capability_results"][number],
  ): string {
    return row.capability_name?.trim() || row.capability_id;
  }
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
      {#if onCancel}
        <button
          type="button"
          class="analysis-report-button"
          disabled={document.cancelInProgress}
          onclick={() => void onCancel?.()}
        >
          {document.cancelInProgress ? "Cancelling…" : "Cancel evaluation"}
        </button>
      {/if}
    </section>
  {:else if document.status === "loading"}
    <section class="analysis-report-status" aria-live="polite">
      <ReportProgress
        progress={document.loadProgress}
        waitingMessage="Loading analysis report..."
        label="assembly steps completed"
      />
    </section>
  {:else if document.status === "error"}
    <section class="analysis-report-status" aria-live="polite">
      <p>{document.errorReason || "Failed to load the analysis report."}</p>
    </section>
  {:else if document.status === "cancelled"}
    <section class="analysis-report-status" aria-live="polite">
      <p>Evaluation cancelled.</p>
    </section>
  {:else if document.status === "loaded" && document.reportData}
    <Tabs.Root
      class="analysis-report-tabs"
      orientation="vertical"
      value={activeTab}
      onValueChange={(value) => (activeTab = value)}
    >
      <Tabs.List class="analysis-report-tab-list" aria-label="Report views">
        <Tabs.Trigger class="analysis-report-tab" value="report"
          >Report</Tabs.Trigger
        >
        <Tabs.Trigger class="analysis-report-tab" value="statistical-analysis"
          >Statistical analysis</Tabs.Trigger
        >
      </Tabs.List>
      <Tabs.Content class="analysis-report-tab-panel" value="report">
        <section
          class="analysis-report-section"
          aria-labelledby="summary-title"
        >
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
              <dd>
                {#if document.openSourceGraph}
                  <button
                    type="button"
                    class="analysis-report-link"
                    onclick={() => void document.openSourceGraph?.()}
                    title={document.reportData.source_graph_revision_id}
                  >
                    {document.reportData.source_graph_title}
                  </button>
                {:else}
                  {document.reportData.source_graph_title}
                {/if}
              </dd>
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
                  <th scope="col">Model variant</th>
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
                    <th scope="row">
                      {#if document.openOptimization && canOpenPlan(plan)}
                        <button
                          type="button"
                          class="analysis-report-link"
                          onclick={() => document.openOptimization?.(plan)}
                          title={plan.id}
                        >
                          {plan.strategy}
                        </button>
                      {:else}
                        <span
                          title={canOpenPlan(plan)
                            ? plan.id
                            : "Report not ready yet"}>{plan.strategy}</span
                        >
                      {/if}
                    </th>
                    <td>{plan.model_variant}</td>
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
                    <th scope="row">
                      {#if document.openExperiment && canOpenExperiment(experiment)}
                        <button
                          type="button"
                          class="analysis-report-link"
                          onclick={() => document.openExperiment?.(experiment)}
                          title={experiment.id}
                        >
                          {experiment.id.slice(0, 8)}
                        </button>
                      {:else}
                        <span title={experiment.id}
                          >{experiment.id.slice(0, 8)}</span
                        >
                      {/if}
                    </th>
                    <td>
                      {#if experiment.optimization_run_id}
                        {@const linkedPlan = document.reportData.plans.find(
                          (p) => p.id === experiment.optimization_run_id,
                        )}
                        {#if linkedPlan && document.openOptimization && canOpenPlan(linkedPlan)}
                          <button
                            type="button"
                            class="analysis-report-link"
                            onclick={() =>
                              document.openOptimization?.(linkedPlan)}
                            title={experiment.optimization_run_id}
                          >
                            {experiment.optimization_run_id.slice(0, 8)}
                          </button>
                        {:else if !linkedPlan && document.openOptimization && document.reportData.status !== "running"}
                          <button
                            type="button"
                            class="analysis-report-link"
                            onclick={() =>
                              document.openOptimization?.({
                                id: experiment.optimization_run_id!,
                              })}
                            title={experiment.optimization_run_id}
                          >
                            {experiment.optimization_run_id.slice(0, 8)}
                          </button>
                        {:else}
                          <span title={experiment.optimization_run_id}
                            >{experiment.optimization_run_id.slice(0, 8)}</span
                          >
                        {/if}
                      {:else}
                        baseline
                      {/if}
                    </td>
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
      </Tabs.Content>
      <Tabs.Content
        class="analysis-report-tab-panel"
        value="statistical-analysis"
      >
        <section
          class="analysis-report-section"
          aria-labelledby="statistical-analysis-title"
        >
          <h2 id="statistical-analysis-title">Statistical analysis</h2>
          <p class="analysis-report-note">
            Pilot analysis is planning-only. Final results use tested strategy
            minus baseline; intervals show simulator uncertainty only.
          </p>
          <div class="analysis-report-actions">
            <button
              type="button"
              class="analysis-report-button"
              disabled={api == null ||
                document.pilotAnalysis.status === "loading"}
              onclick={() =>
                api && void document.startAnalysis(api, document.id, "pilot")}
            >
              {document.pilotAnalysis.status === "loading"
                ? "Running pilot…"
                : "Run pilot"}
            </button>
            <button
              type="button"
              class="analysis-report-button"
              disabled={api == null ||
                document.finalAnalysis.status === "loading"}
              onclick={() =>
                api && void document.startAnalysis(api, document.id, "analyze")}
            >
              {document.finalAnalysis.status === "loading"
                ? "Running final analysis…"
                : "Run final analysis"}
            </button>
          </div>
          {#if document.pilotAnalysis.error}<p
              class="analysis-report-analysis-error"
              aria-live="assertive"
            >
              {document.pilotAnalysis.error}
            </p>{/if}
          {#if document.finalAnalysis.error}<p
              class="analysis-report-analysis-error"
              aria-live="assertive"
            >
              {document.finalAnalysis.error}
            </p>{/if}
          {#if document.pilotAnalysis.data}
            <h3>Pilot planning results</h3>
            <div class="analysis-report-table-wrap">
              <table class="analysis-report-table">
                <thead
                  ><tr
                    ><th scope="col">Comparison</th><th scope="col"
                      >Half-width</th
                    ><th scope="col">Target</th><th scope="col">Pass/fail</th
                    ><th scope="col">Paired seeds</th><th scope="col"
                      >Estimated required trials</th
                    ></tr
                  ></thead
                ><tbody>
                  {#each document.pilotAnalysis.data.pilot_comparison_pass as row (row.comparison)}<tr
                      ><td>{formatNumber(row.comparison)}</td><td
                        >{formatNumber(row.ci_half_width)}</td
                      ><td>{formatNumber(row.target)}</td><td
                        >{row.passes == null
                          ? "—"
                          : row.passes
                            ? "Pass"
                            : "Fail"}</td
                      ><td>{formatValue(row.paired_attack_seed_count)}</td><td
                        >{formatValue(row.approximate_trials)}</td
                      ></tr
                    >{/each}
                </tbody>
              </table>
            </div>
          {/if}
          {#if document.finalAnalysis.data}
            {@const analysis = document.finalAnalysis.data}
            <h3>Final analysis</h3>
            <KpiCards metrics={metadataKpis(analysis.metadata)} />
            <section
              class="analysis-report-reproducibility"
              aria-labelledby="reproducibility-title"
            >
              <h3 id="reproducibility-title">Reproducibility</h3>
              {#snippet metadataRows(
                rows: readonly (readonly [string, unknown])[],
              )}
                <dl class="analysis-report-metadata">
                  {#each rows as [label, value] (label)}
                    <div class="analysis-report-metadata-row">
                      <dt>{label}</dt>
                      <dd>
                        {#if typeof value === "object" && value !== null}
                          <pre>{formatMetadataValue(value)}</pre>
                        {:else}
                          {formatMetadataValue(value)}
                        {/if}
                      </dd>
                    </div>
                  {/each}
                </dl>
              {/snippet}
              {@render metadataRows([
                ["Manifest ID", analysis.metadata.manifest_id],
                ["Model variants", analysis.metadata.model_variants],
                ["Checksums hash", analysis.metadata.checksums_hash],
                ["Estimand", analysis.metadata.estimand_note],
              ])}
              {#each [["Input hashes", analysis.metadata.input_hashes], ["Analysis configuration", analysis.metadata.analysis_configuration], ["Dependencies", analysis.metadata.dependencies]] as [title, values] (title)}
                {@const rows = metadataEntries(values)}
                <section class="analysis-report-metadata-group">
                  <h4>{title}</h4>
                  {#if rows.length > 0}
                    {@render metadataRows(rows)}
                  {:else}
                    <p>—</p>
                  {/if}
                </section>
              {/each}
            </section>
            <h3>Primary results</h3>
            <div class="analysis-report-table-wrap">
              <table class="analysis-report-table">
                <thead
                  ><tr
                    ><th scope="col">Strategy (tested model)</th><th scope="col"
                      >Baseline (model)</th
                    ><th scope="col">Budget</th><th scope="col">Comparison</th
                    ><th scope="col">CI half-width</th><th scope="col"
                      >CI lower</th
                    ><th scope="col">CI upper</th><th scope="col">Outcome</th
                    ><th scope="col">Paired mean difference</th><th scope="col"
                      >d_z</th
                    ><th scope="col">p raw</th><th scope="col">p adjusted</th
                    ></tr
                  ></thead
                ><tbody
                  >{#each analysis.primary_results as row (row.comparison)}<tr
                      ><td>{row.strategy} ({row.model_variant})</td><td
                        >{row.baseline} ({row.baseline_model_variant})</td
                      ><td>{row.budget}</td><td
                        >{formatNumber(row.comparison)}</td
                      ><td>{formatNumber(row.ci_half_width)}</td><td
                        >{formatNumber(row.ci_lower)}</td
                      ><td>{formatNumber(row.ci_upper)}</td><td
                        >{row.outcome}</td
                      ><td>{formatNumber(row.paired_mean_difference)}</td><td
                        >{formatNumber(row.d_z)}</td
                      ><td>{formatNumber(row.p_raw)}</td><td
                        >{formatNumber(row.p_adjusted)}</td
                      ></tr
                    >{/each}</tbody
                >
              </table>
            </div>
            <h3>Secondary results</h3>
            <div class="analysis-report-table-wrap">
              <table class="analysis-report-table">
                <thead
                  ><tr
                    ><th scope="col">Strategy (tested model)</th><th scope="col"
                      >Baseline (model)</th
                    ><th scope="col">Budget</th><th scope="col">Comparison</th
                    ><th scope="col">CI half-width</th><th scope="col"
                      >CI lower</th
                    ><th scope="col">CI upper</th><th scope="col">Outcome</th
                    ><th scope="col">Mean difference</th></tr
                  ></thead
                ><tbody
                  >{#each analysis.secondary_results as row (row.comparison)}<tr
                      ><td>{row.strategy} ({row.model_variant})</td><td
                        >{row.baseline} ({row.baseline_model_variant})</td
                      ><td>{row.budget}</td><td
                        >{formatNumber(row.comparison)}</td
                      ><td>{formatNumber(row.ci_half_width)}</td><td
                        >{formatNumber(row.ci_lower)}</td
                      ><td>{formatNumber(row.ci_upper)}</td><td
                        >{row.outcome}</td
                      ><td>{formatNumber(row.mean_difference)}</td></tr
                    >{/each}</tbody
                >
              </table>
            </div>
            <h3>Capability results</h3>
            <div class="analysis-report-table-wrap">
              <table class="analysis-report-table">
                <thead
                  ><tr
                    ><th scope="col">Capability</th><th scope="col"
                      >Strategy (tested model)</th
                    ><th scope="col">Baseline (model)</th><th scope="col"
                      >Budget</th
                    ><th scope="col">Comparison</th><th scope="col"
                      >Baseline probability</th
                    ><th scope="col">Tested probability</th><th scope="col"
                      >Difference</th
                    ><th scope="col">CI half-width</th><th scope="col"
                      >CI lower</th
                    ><th scope="col">CI upper</th></tr
                  ></thead
                ><tbody
                  >{#each analysis.capability_results as row (`${row.comparison}:${row.capability_id}`)}<tr
                      ><td
                        >{#if document.openSourceGraph}
                          <button
                            type="button"
                            class="analysis-report-link"
                            onclick={() =>
                              void document.openSourceGraph?.(
                                row.capability_id,
                              )}
                            title={row.capability_id}
                            >{capabilityName(row)}</button
                          >
                        {:else}
                          {capabilityName(row)}
                        {/if}</td
                      ><td>{row.strategy} ({row.model_variant})</td><td
                        >{row.baseline} ({row.baseline_model_variant})</td
                      ><td>{row.budget}</td><td
                        >{formatNumber(row.comparison)}</td
                      ><td>{formatNumber(row.baseline_probability)}</td><td
                        >{formatNumber(row.tested_probability)}</td
                      ><td>{formatNumber(row.probability_difference)}</td><td
                        >{formatNumber(row.ci_half_width)}</td
                      ><td>{formatNumber(row.ci_lower)}</td><td
                        >{formatNumber(row.ci_upper)}</td
                      ></tr
                    >{/each}</tbody
                >
              </table>
            </div>
          {/if}
        </section>
      </Tabs.Content>
    </Tabs.Root>
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

  :global(.analysis-report-tabs) {
    display: flex;
    align-items: flex-start;
    gap: var(--ui-space-6);
  }

  :global(.analysis-report-tab-list) {
    display: flex;
    flex-direction: column;
    flex: 0 0 12rem;
    gap: var(--ui-space-1);
  }

  :global(.analysis-report-tab),
  .analysis-report-button {
    padding: var(--ui-space-2) var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    color: inherit;
    font: inherit;
    cursor: pointer;
  }

  :global(.analysis-report-tab[data-state="active"]) {
    border-color: var(--ui-color-accent);
    color: var(--ui-color-accent);
  }

  :global(.analysis-report-tab-panel) {
    min-width: 0;
    flex: 1;
  }

  .analysis-report-actions {
    display: flex;
    flex-wrap: wrap;
    gap: var(--ui-space-2);
    margin: var(--ui-space-3) 0;
  }
  .analysis-report-button:disabled {
    cursor: wait;
    opacity: 0.65;
  }
  .analysis-report-note,
  .analysis-report-analysis-error {
    margin: var(--ui-space-2) 0;
    color: var(--ui-color-text-secondary);
  }
  .analysis-report-analysis-error {
    color: var(--ui-color-danger, var(--ui-color-accent));
  }
  h3 {
    margin: var(--ui-space-6) 0 var(--ui-space-3);
    font-size: var(--ui-text-base);
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

  .analysis-report-reproducibility,
  .analysis-report-metadata {
    min-width: 0;
  }

  .analysis-report-reproducibility {
    margin-top: var(--ui-space-6);
  }

  .analysis-report-metadata {
    display: grid;
    gap: var(--ui-space-2);
  }

  .analysis-report-metadata-row {
    min-width: 0;
    display: grid;
    grid-template-columns: minmax(10rem, 15rem) minmax(0, 1fr);
    gap: var(--ui-space-3);
    align-items: start;
    padding: var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }

  .analysis-report-metadata-row dt {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    font-weight: 600;
    text-transform: uppercase;
  }

  .analysis-report-metadata-row dd {
    min-width: 0;
    margin: 0;
    overflow-wrap: anywhere;
  }

  .analysis-report-metadata-row pre {
    max-width: 100%;
    max-height: 16rem;
    margin: 0;
    overflow: auto;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    font-family: var(--ui-font-mono);
    font-size: var(--ui-text-sm);
  }

  .analysis-report-metadata-group h4 {
    margin: var(--ui-space-4) 0 var(--ui-space-2);
    font-size: var(--ui-text-sm);
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

  .analysis-report-link {
    padding: 0;
    border: 0;
    background: transparent;
    color: var(--ui-color-accent);
    font: inherit;
    text-decoration: underline;
    text-underline-offset: 2px;
    cursor: pointer;
  }

  .analysis-report-link:hover {
    color: var(--ui-color-accent-strong, var(--ui-color-accent));
  }

  .analysis-report-link:focus-visible {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: 2px;
    border-radius: 2px;
  }

  @media (max-width: 48em) {
    .analysis-report {
      padding: var(--ui-space-4);
    }
    :global(.analysis-report-tabs) {
      flex-direction: column;
      gap: var(--ui-space-4);
    }
    :global(.analysis-report-tab-list) {
      flex-basis: auto;
      width: 100%;
    }
    .analysis-report-metadata-row {
      grid-template-columns: 1fr;
      gap: var(--ui-space-1);
    }
  }
</style>
