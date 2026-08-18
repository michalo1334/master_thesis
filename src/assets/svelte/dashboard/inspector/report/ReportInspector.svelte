<script lang="ts">
  import type { AnalysisOption } from "../../dashboard-api";
  import type { OptimizationReportDocument } from "../../optimization-report/OptimizationReportDocument.svelte";
  import type { SimulationReportDocument } from "../../simulation-report/SimulationReportDocument.svelte";
  import Inspector from "../Inspector.svelte";

  interface Props {
    document: SimulationReportDocument | OptimizationReportDocument;
    analyses: readonly AnalysisOption[];
    onAnalysisChange: (analysisId: string | null) => Promise<boolean>;
  }

  let { document, analyses, onAnalysisChange }: Props = $props();
  let saving = $state(false);
  let status = $state("");
  let reportId = $derived(document.reportId);

  async function changeAnalysis(event: Event): Promise<void> {
    if (saving) return;
    const analysisId = (event.currentTarget as HTMLSelectElement).value || null;
    saving = true;
    status = "Saving…";
    try {
      status = (await onAnalysisChange(analysisId))
        ? "Saved."
        : "Could not update analysis.";
    } catch {
      status = "Could not update analysis.";
    } finally {
      saving = false;
    }
  }
</script>

<Inspector title="Report">
  <label class="report-analysis-field">
    <span>Analysis</span>
    <select
      aria-label="Analysis"
      value={document.analysisId ?? ""}
      disabled={saving || !reportId}
      onchange={changeAnalysis}
    >
      <option value="">No analysis</option>
      {#each analyses as analysis (analysis.id)}
        <option value={analysis.id}>{analysis.title}</option>
      {/each}
    </select>
  </label>
  {#if status}
    <p class="report-analysis-status" role="status">{status}</p>
  {/if}
</Inspector>

<style>
  .report-analysis-field {
    display: grid;
    gap: var(--ds-space-1);
  }
  .report-analysis-field > span {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-xs);
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }
  .report-analysis-field select {
    min-width: 0;
    min-height: var(--ds-control-height);
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-surface);
  }
  .report-analysis-status {
    margin: var(--ds-space-2) 0 0;
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
  }
</style>
