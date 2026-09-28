<script lang="ts">
  import type {
    EvaluationAnalysis,
    EvaluationAnalysisMetadata,
  } from "../../contracts.generated/dashboard/evaluation";
  import KpiCards, { type KpiMetric } from "../KpiCards.svelte";
  import { formatRuntime } from "../format";

  interface Props {
    analysis: EvaluationAnalysis;
  }

  let { analysis }: Props = $props();

  const formatNumber = (value: number | null | undefined): string =>
    value == null || !Number.isFinite(value) ? "—" : value.toFixed(3);
  const formatCount = (value: number | null | undefined): string =>
    value == null || !Number.isInteger(value) ? "—" : String(value);
  const formatValue = (value: unknown): string =>
    value == null
      ? "—"
      : typeof value === "number"
        ? formatNumber(value)
        : String(value);
  const formatBoolean = (value: boolean | null | undefined): string =>
    value == null ? "—" : value ? "Yes" : "No";
  const formatMetadataValue = (value: unknown): string => {
    if (value == null) return "—";
    if (typeof value === "object") return JSON.stringify(value, null, 2);
    return formatValue(value);
  };
  const metadataEntries = (value: unknown): [string, unknown][] =>
    value && typeof value === "object" && !Array.isArray(value)
      ? Object.entries(value)
      : [];
  const rowClass = (informative: boolean | null | undefined): string =>
    informative === false ? "study-analysis-row-non-informative" : "";

  const metadataKpis = (metadata: EvaluationAnalysisMetadata): KpiMetric[] => {
    const metrics: KpiMetric[] = [
      {
        label: "Mode",
        value: metadata.command_mode,
        detail: "Analysis command",
        tone: "neutral",
      },
      {
        label: metadata.model_version == null ? "Study" : "Model",
        value: metadata.model_version ?? metadata.study_id ?? "—",
        detail:
          metadata.model_version == null
            ? "Study identifier"
            : "Statistical model",
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
        value: formatCount(
          metadata.schema_version ?? metadata.specification_version,
        ),
        detail: "Analysis result schema",
        tone: "neutral",
      },
      {
        label: "Package version",
        value: formatValue(metadata.package_version),
        detail: "Analysis package",
        tone: "neutral",
      },
    ];

    if (metadata.family_scope != null) {
      metrics.push(
        {
          label: "Family scope",
          value: metadata.family_scope,
          detail: "Multiplicity correction family",
          tone: "neutral",
        },
        {
          label: "Family size",
          value: formatValue(metadata.family_size),
          detail: "Declared primary comparisons",
          tone: "neutral",
        },
      );
    }

    if (metadata.insufficient_pilot != null) {
      metrics.push({
        label: "Pilot recommendation",
        value: metadata.insufficient_pilot ? "Insufficient" : "Recommended",
        detail: "Precision pilot outcome",
        tone: metadata.insufficient_pilot ? "warning" : "positive",
      });
    }

    return metrics;
  };

  const isPilot = $derived(
    analysis.metadata.command_mode === "pilot" ||
      analysis.metadata.command_mode === "study-pilot",
  );
  const pilotRows = $derived(analysis.pilot_results);
  const primaryRows = $derived(analysis.primary_results);
  const insufficientPilot = $derived(
    analysis.metadata.insufficient_pilot === true,
  );
  const nonInformativePilotComparisons = $derived(
    new Set(
      pilotRows
        .filter((row) => row.informative === false)
        .map((row) => row.comparison_id ?? "unknown"),
    ).size,
  );
  const hasNonInformativePrimary = $derived(
    primaryRows.some((row) => row.informative === false),
  );
</script>

{#snippet testedStrategyCell(row: { strategy: string; model_variant: string })}
  <td>{row.strategy} ({row.model_variant})</td>
{/snippet}

{#snippet baselineStrategyCell(row: {
  baseline: string;
  baseline_model_variant: string;
})}
  <td>{row.baseline} ({row.baseline_model_variant})</td>
{/snippet}

{#snippet intervalCells(row: {
  ci_half_width?: number | null;
  ci_lower?: number | null;
  ci_upper?: number | null;
})}
  <td>{formatNumber(row.ci_half_width)}</td>
  <td>{formatNumber(row.ci_lower)}</td>
  <td>{formatNumber(row.ci_upper)}</td>
{/snippet}

{#snippet metadataRows(rows: readonly (readonly [string, unknown])[])}
  <dl class="study-analysis-metadata">
    {#each rows as [label, value] (label)}
      <div class="study-analysis-metadata-row">
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

<section class="study-analysis" aria-label="Study analysis">
  {#if isPilot}
    <h2>Pilot planning results</h2>
    {#if nonInformativePilotComparisons > 0}
      <p class="study-analysis-blocking" role="alert">
        Blocking: {nonInformativePilotComparisons} pilot comparison(s) are non-informative.
        A zero-width non-informative result is not a pass.
      </p>
    {/if}
    <dl class="study-analysis-summary">
      <div>
        <dt>Recommended plan count</dt>
        <dd>
          {formatCount(analysis.metadata.recommended_plan_selection_seed_count)}
        </dd>
      </div>
      <div>
        <dt>Recommended attacks per plan</dt>
        <dd>{formatCount(analysis.metadata.recommended_attacks_per_plan)}</dd>
      </div>
      <div>
        <dt>Pilot state</dt>
        <dd>
          {insufficientPilot
            ? "Insufficient pilot"
            : "Recommendation available"}
        </dd>
      </div>
      <div>
        <dt>Non-informative comparisons</dt>
        <dd>{nonInformativePilotComparisons}</dd>
      </div>
    </dl>
    <div class="study-analysis-table-wrap">
      <table class="study-analysis-table">
        <thead>
          <tr>
            <th scope="col">Tier</th>
            <th scope="col">Comparison</th>
            <th scope="col">Candidate plans</th>
            <th scope="col">Candidate attacks per plan</th>
            <th scope="col">Guarded half-width</th>
            <th scope="col">Target</th>
            <th scope="col">Informative</th>
            <th scope="col">Pass</th>
          </tr>
        </thead>
        <tbody>
          {#each pilotRows as row (`${row.comparison_id}:${row.candidate_plan_count}:${row.candidate_attacks_per_plan}`)}
            <tr class={rowClass(row.informative)}>
              <td>{formatValue(row.tier)}</td>
              <td>{formatValue(row.comparison_id)}</td>
              <td>{formatCount(row.candidate_plan_count)}</td>
              <td>{formatCount(row.candidate_attacks_per_plan)}</td>
              <td>{formatNumber(row.guarded_ci_half_width)}</td>
              <td>{formatNumber(row.target)}</td>
              <td>{formatBoolean(row.informative)}</td>
              <td>{row.passes == null ? "—" : row.passes ? "Pass" : "Fail"}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {:else}
    <h2>Final analysis</h2>
    <KpiCards metrics={metadataKpis(analysis.metadata)} />
    {#if analysis.metadata.runtime_summary}
      <section
        class="study-analysis-runtime"
        aria-labelledby="runtime-summary-title"
      >
        <h3 id="runtime-summary-title">Archive runtime summary</h3>
        <dl class="study-analysis-summary">
          <div>
            <dt>Median plan selection</dt>
            <dd>
              {formatRuntime(
                analysis.metadata.runtime_summary
                  .median_plan_selection_runtime_ms,
              )}
            </dd>
          </div>
          <div>
            <dt>Median simulation</dt>
            <dd>
              {formatRuntime(
                analysis.metadata.runtime_summary.median_simulation_runtime_ms,
              )}
            </dd>
          </div>
          <div>
            <dt>Total evaluator</dt>
            <dd>
              {formatRuntime(
                analysis.metadata.runtime_summary.evaluator_runtime_ms,
              )}
            </dd>
          </div>
        </dl>
      </section>
    {/if}
    <section
      class="study-analysis-feasibility"
      aria-labelledby="feasibility-summary-title"
    >
      <h3 id="feasibility-summary-title">Pre-attack feasibility</h3>
      <div class="study-analysis-table-wrap">
        <table class="study-analysis-table">
          <thead
            ><tr
              ><th scope="col">Experiment</th><th scope="col">Plan</th><th
                scope="col">Direct feasibility</th
              ><th scope="col">Unavailable required flows</th><th scope="col"
                >Affected capabilities</th
              ></tr
            ></thead
          >
          <tbody>
            {#each analysis.feasibility_summary as row (row.experiment_id)}
              <tr>
                <th scope="row" title={row.experiment_id}
                  >{row.experiment_id.slice(0, 8)}</th
                >
                <td title={row.plan_id}>{row.plan_id || "Baseline"}</td>
                <td>{row.pre_attack_feasible ? "Feasible" : "Infeasible"}</td>
                <td>{row.unavailable_required_flow_count}</td>
                <td>{row.affected_capability_count}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </section>
    <section
      class="study-analysis-reproducibility"
      aria-labelledby="reproducibility-title"
    >
      <h3 id="reproducibility-title">Reproducibility</h3>
      {@render metadataRows([
        ["Model variants", analysis.metadata.model_variants],
        ["Checksums hash", analysis.metadata.checksums_hash],
        ["Estimand", analysis.metadata.estimand_note],
      ])}
      {#each [["Input hashes", analysis.metadata.input_hashes], ["Analysis configuration", analysis.metadata.analysis_configuration], ["Dependencies", analysis.metadata.dependencies]] as [title, values] (title)}
        {@const rows = metadataEntries(values)}
        <section class="study-analysis-metadata-group">
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
    <p class="study-analysis-note study-analysis-family-label">
      Holm adjustment covers the complete declared study family.
    </p>
    {#if hasNonInformativePrimary}
      <p class="study-analysis-blocking" role="alert">
        Blocking: one or more primary comparisons are non-informative. A
        zero-width non-informative result is not a pass.
      </p>
    {/if}
    <div class="study-analysis-table-wrap">
      <table class="study-analysis-table">
        <thead
          ><tr
            ><th scope="col">Tier</th><th scope="col">Comparison</th><th
              scope="col">Comparison ID</th
            ><th scope="col">Strategy (tested model)</th><th scope="col"
              >Baseline (model)</th
            ><th scope="col">Budget</th><th scope="col">Tested plans</th><th
              scope="col">Baseline plans</th
            ><th scope="col">Attacks per plan</th><th scope="col"
              >Informative</th
            ><th scope="col">CI half-width</th><th scope="col">CI lower</th><th
              scope="col">CI upper</th
            ><th scope="col">Outcome</th><th scope="col"
              >Paired mean difference</th
            ><th scope="col">d_z</th><th scope="col">p raw</th><th scope="col"
              >p adjusted</th
            ></tr
          ></thead
        >
        <tbody>
          {#each primaryRows as row (`study-${row.comparison_id}`)}
            <tr class={rowClass(row.informative)}>
              <td>{formatValue(row.tier)}</td><td
                >{formatNumber(row.comparison)}</td
              ><td>{formatValue(row.comparison_id)}</td
              >{@render testedStrategyCell(row)}{@render baselineStrategyCell(
                row,
              )}<td>{row.budget}</td><td
                >{formatCount(row.tested_plan_count)}</td
              ><td>{formatCount(row.baseline_plan_count)}</td><td
                >{formatCount(row.attacks_per_plan)}</td
              ><td>{formatBoolean(row.informative)}</td>{@render intervalCells(
                row,
              )}<td>{row.outcome}</td><td
                >{formatNumber(row.paired_mean_difference)}</td
              ><td>{formatNumber(row.d_z)}</td><td>{formatNumber(row.p_raw)}</td
              ><td>{formatNumber(row.p_adjusted)}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    <h3>Secondary results</h3>
    <div class="study-analysis-table-wrap">
      <table class="study-analysis-table">
        <thead
          ><tr
            ><th scope="col">Strategy (tested model)</th><th scope="col"
              >Baseline (model)</th
            ><th scope="col">Budget</th><th scope="col">Comparison</th><th
              scope="col">CI half-width</th
            ><th scope="col">CI lower</th><th scope="col">CI upper</th><th
              scope="col">Outcome</th
            ><th scope="col">Mean difference</th></tr
          ></thead
        >
        <tbody
          >{#each analysis.secondary_results as row (row.comparison)}<tr
              >{@render testedStrategyCell(row)}{@render baselineStrategyCell(
                row,
              )}<td>{row.budget}</td><td>{formatNumber(row.comparison)}</td
              >{@render intervalCells(row)}<td>{row.outcome}</td><td
                >{formatNumber(row.mean_difference)}</td
              ></tr
            >{/each}</tbody
        >
      </table>
    </div>
    <h3>Capability results</h3>
    <div class="study-analysis-table-wrap">
      <table class="study-analysis-table">
        <thead
          ><tr
            ><th scope="col">Capability</th><th scope="col"
              >Strategy (tested model)</th
            ><th scope="col">Baseline (model)</th><th scope="col">Budget</th><th
              scope="col">Comparison</th
            ><th scope="col">Baseline probability</th><th scope="col"
              >Tested probability</th
            ><th scope="col">Difference</th><th scope="col">CI half-width</th
            ><th scope="col">CI lower</th><th scope="col">CI upper</th></tr
          ></thead
        >
        <tbody
          >{#each analysis.capability_results as row (`${row.comparison}:${row.capability_id}`)}<tr
              ><td>{row.capability_name?.trim() || row.capability_id}</td
              >{@render testedStrategyCell(row)}{@render baselineStrategyCell(
                row,
              )}<td>{row.budget}</td><td>{formatNumber(row.comparison)}</td><td
                >{formatNumber(row.baseline_probability)}</td
              ><td>{formatNumber(row.tested_probability)}</td><td
                >{formatNumber(row.probability_difference)}</td
              >{@render intervalCells(row)}</tr
            >{/each}</tbody
        >
      </table>
    </div>
  {/if}
</section>

<style>
  .study-analysis {
    max-width: 70rem;
  }
  h2 {
    margin: 0 0 var(--ui-space-3);
    font-size: var(--ui-text-base);
  }
  h3 {
    margin: var(--ui-space-6) 0 var(--ui-space-3);
    font-size: var(--ui-text-base);
  }
  .study-analysis-summary {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
    gap: var(--ui-space-3);
  }
  .study-analysis-summary div {
    padding: var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }
  .study-analysis-summary dt,
  .study-analysis-metadata-row dt {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    font-weight: 600;
    text-transform: uppercase;
  }
  .study-analysis-summary dd {
    margin: var(--ui-space-1) 0 0;
  }
  .study-analysis-runtime,
  .study-analysis-feasibility,
  .study-analysis-reproducibility {
    margin-top: var(--ui-space-6);
  }
  .study-analysis-table-wrap {
    overflow-x: auto;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }
  .study-analysis-table {
    width: 100%;
    border-collapse: collapse;
    text-align: left;
    font-size: var(--ui-text-sm);
  }
  .study-analysis-table th,
  .study-analysis-table td {
    padding: var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border);
    white-space: nowrap;
  }
  .study-analysis-table thead th {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    text-transform: uppercase;
  }
  .study-analysis-table tbody tr:last-child > * {
    border-bottom: 0;
  }
  .study-analysis-note {
    margin: var(--ui-space-2) 0;
    color: var(--ui-color-text-secondary);
  }
  .study-analysis-family-label {
    font-weight: 600;
  }
  .study-analysis-blocking {
    margin: var(--ui-space-2) 0;
    padding: var(--ui-space-3);
    border: 1px solid var(--ui-color-danger, var(--ui-color-accent));
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    color: var(--ui-color-danger, var(--ui-color-accent));
    font-weight: 600;
  }
  .study-analysis-row-non-informative > * {
    color: var(--ui-color-danger, var(--ui-color-accent));
  }
  .study-analysis-metadata {
    display: grid;
    gap: var(--ui-space-2);
    min-width: 0;
  }
  .study-analysis-metadata-row {
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
  .study-analysis-metadata-row dd {
    min-width: 0;
    margin: 0;
    overflow-wrap: anywhere;
  }
  .study-analysis-metadata-row pre {
    max-width: 100%;
    max-height: 16rem;
    margin: 0;
    overflow: auto;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    font-family: var(--ui-font-mono);
    font-size: var(--ui-text-sm);
  }
  .study-analysis-metadata-group h4 {
    margin: var(--ui-space-4) 0 var(--ui-space-2);
    font-size: var(--ui-text-sm);
  }
  .study-analysis-metadata-group p {
    margin: 0;
  }
  @media (max-width: 48em) {
    .study-analysis-metadata-row {
      grid-template-columns: 1fr;
      gap: var(--ui-space-1);
    }
  }
</style>
