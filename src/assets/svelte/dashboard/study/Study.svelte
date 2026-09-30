<script lang="ts">
  import { Tabs } from "bits-ui";
  import StudyAnalysis from "../analysis-report/StudyAnalysis.svelte";
  import type { DashboardApi } from "../dashboard-api";
  import { formatTimestamp } from "../format";
  import type { StudyDocument } from "./StudyDocument.svelte";
  import StudyRunPicker from "./StudyRunPicker.svelte";
  import {
    formatStudyRunError,
    STUDY_PHASE_LABELS,
    STUDY_PHASES,
    type StudyMode,
  } from "./study-types";

  interface Props {
    document: StudyDocument;
    api?: DashboardApi;
  }

  let { document, api }: Props = $props();

  const statusLabel = $derived(byStatus());

  // The Final mapping picker needs the API to load runs and preflight. The
  // workspace passes it as a prop, so bind it once the view renders.
  $effect(() => {
    if (api) document.attachApi(api);
  });

  function handleFinalPickerOpenChange(open: boolean): void {
    if (!open) document.finalMapping.closePicker();
  }

  function selectFinalRun(runId: string): void {
    const tier = document.finalMapping.pickerTier;
    if (tier) document.finalMapping.selectRun(tier, runId);
  }

  const resultTabs = [
    { value: "pilot", label: "Pilot" },
    { value: "final", label: "Final" },
  ] as const;

  function byStatus(): string {
    if (document.status === "failed") return "Failed";
    if (document.running) {
      return document.mode === "final"
        ? "Final analysis running"
        : "Pilot analysis running";
    }
    if (document.finalResult) return "Final analysis complete";
    if (document.pilotResult) {
      return document.pilotEligible
        ? "Pilot eligible for final analysis"
        : "Pilot stopped";
    }
    return "Ready to run";
  }

  function selectResultTab(value: string): void {
    if (value === "pilot" || value === "final") {
      document.activeResultTab = value;
    }
  }

  function resultFor(mode: StudyMode) {
    return mode === "pilot" ? document.pilotResult : document.finalResult;
  }

  function downloadLabel(mode: StudyMode): string {
    return `Download ${mode === "pilot" ? "pilot" : "final"} result ZIP`;
  }

  function emptyResultMessage(mode: StudyMode): string {
    if (document.running) {
      return mode === "final"
        ? "Final analysis is running."
        : "Pilot analysis is running.";
    }
    if (mode === "final") {
      return document.pilotEligible
        ? "Run final to produce the final analysis."
        : "Final analysis needs an eligible pilot.";
    }
    return "The pilot analysis has not produced a result.";
  }
</script>

<article
  class="study-document"
  data-study-document={document.id}
  tabindex="-1"
  aria-labelledby={`study-document-title-${document.id}`}
>
  <header class="study-document-header">
    <h1 id={`study-document-title-${document.id}`}>{document.title}</h1>
    <p class="study-document-status" role="status">{statusLabel}</p>
  </header>

  <dl class="study-document-meta">
    <div>
      <dt>Study</dt>
      <dd>{document.locked.study_id}</dd>
    </div>
    <div>
      <dt>Specification version</dt>
      <dd>{document.locked.specification_version}</dd>
    </div>
    <div>
      <dt>Mode</dt>
      <dd>{document.mode ?? "—"}</dd>
    </div>
    <div>
      <dt>Declared tiers</dt>
      <dd>{document.tierCount}</dd>
    </div>
  </dl>

  <section class="study-document-section" aria-label="Pilot tier mapping">
    <h2>Pilot tier mapping</h2>
    <table class="study-document-table">
      <thead>
        <tr>
          <th scope="col">Tier</th>
          <th scope="col">Run</th>
          <th scope="col">Graph</th>
          <th scope="col">Plans / trials</th>
        </tr>
      </thead>
      <tbody>
        {#each document.locked.tiers as tier (tier.tier)}
          <tr>
            <th scope="row">{tier.tier}</th>
            <td>{tier.manifest_title ?? "Untitled run"}</td>
            <td>{tier.graph_title ?? "—"}</td>
            <td>{tier.plan_count ?? 0} / {tier.trial_count ?? 0}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </section>

  <section class="study-document-section" aria-label="Analysis phases">
    <h2>Analysis phases</h2>
    <ol class="study-document-phases">
      {#each STUDY_PHASES as phase (phase)}
        <li
          class:study-document-phase-active={document.phase === phase}
          aria-current={document.phase === phase ? "step" : undefined}
        >
          {STUDY_PHASE_LABELS[phase]}
        </li>
      {/each}
    </ol>

    {#if document.running}
      <p class="study-document-note">
        Keep this document open until the analysis completes. Closing the
        document cancels the running task.
      </p>
    {/if}

    {#if document.error}
      <p class="study-document-error" role="alert">{document.error}</p>
    {/if}

    {#if document.closeError}
      <p class="study-document-error" role="alert">{document.closeError}</p>
    {/if}

    {#if document.canRetry}
      <div class="study-document-actions">
        <button
          class="study-button study-confirm"
          type="button"
          onclick={() => void document.retry(api)}
        >
          {document.retryLabel}
        </button>
      </div>
    {/if}
  </section>

  {#if document.pilotEligible && document.finalResult === undefined}
    <section class="study-document-section" aria-label="Final tier mapping">
      <h2>Final tier mapping</h2>
      <p class="study-document-note">
        Final analysis runs on separate completed runs from the final seed
        schedule. Pilot runs stay excluded.
      </p>

      {#if document.finalMapping.isLoading}
        <p class="study-document-note" role="status">
          Loading final-tier runs…
        </p>
      {:else if !document.finalMapping.hasEligibleRuns}
        <p class="study-document-note">
          No completed run qualifies for the final seed schedule.
        </p>
      {:else}
        <table class="study-document-table">
          <thead>
            <tr>
              <th scope="col">Tier</th>
              <th scope="col">Run</th>
              <th scope="col">Graph</th>
              <th scope="col">Completed</th>
              <th scope="col">Action</th>
            </tr>
          </thead>
          <tbody>
            {#each document.finalMapping.tiers as tier (tier)}
              {@const run = document.finalMapping.runFor(tier)}
              <tr>
                <th scope="row">{tier}</th>
                <td>{run?.manifest_title ?? "Not selected"}</td>
                <td>{run?.graph_title ?? "—"}</td>
                <td>
                  {run?.completed_at ? formatTimestamp(run.completed_at) : "—"}
                </td>
                <td class="study-document-actions">
                  <button
                    class="study-button"
                    type="button"
                    disabled={document.finalMapping.locked}
                    aria-label={`${run ? "Change" : "Choose"} final run for tier ${tier}`}
                    onclick={() => document.finalMapping.openPicker(tier)}
                  >
                    {run ? "Change" : "Choose"}
                  </button>
                  {#if run}
                    <button
                      class="study-button"
                      type="button"
                      disabled={document.finalMapping.locked}
                      aria-label={`Clear final run for tier ${tier}`}
                      onclick={() => document.finalMapping.clearRun(tier)}
                    >
                      Clear
                    </button>
                  {/if}
                </td>
              </tr>
              {#if document.finalMapping.missingSelectionMessage(tier)}
                <tr class="study-document-validation">
                  <td colspan="5">
                    {document.finalMapping.missingSelectionMessage(tier)}
                  </td>
                </tr>
              {/if}
            {/each}
          </tbody>
        </table>

        <p class="study-document-note" role="status">
          {document.finalMapping.mappedCount} of {document.finalMapping.tiers
            .length} final tiers mapped
        </p>

        {#if document.finalMapping.hasMissingSelections}
          <p class="study-document-mapping-summary" role="alert">
            Select one completed run for every declared tier.
          </p>
        {/if}

        {#if document.finalMapping.preflightStatus === "loading"}
          <p class="study-document-note" role="status">
            Checking the final bundle…
          </p>
        {:else if document.finalMapping.preflightStatus === "ok"}
          <p class="study-document-note" role="status">
            Final preflight passed.
          </p>
        {:else if document.finalMapping.preflightStatus === "rejected" && document.finalMapping.visiblePreflightErrors.length > 0}
          <ul class="study-document-error" role="alert">
            {#each document.finalMapping.visiblePreflightErrors as error (error.code)}
              <li>{formatStudyRunError(error)}</li>
            {/each}
          </ul>
        {/if}

        {#if document.finalMapping.locked}
          <p class="study-document-note">
            The final mapping is locked. A retry reuses the same runs.
          </p>
        {/if}

        <div class="study-document-actions">
          <button
            class="study-button study-confirm"
            type="button"
            disabled={!document.canRunFinal}
            onclick={() => void document.runFinal(api)}
          >
            Run final
          </button>
        </div>
      {/if}
    </section>
  {/if}

  {#if document.canRerunPilot}
    <section class="study-document-section" aria-label="Run controls">
      <h2>Next step</h2>
      <p class="study-document-warning" role="alert">
        The pilot is insufficient or non-informative, so final analysis stays
        disabled. Deterministic inputs should reproduce the same stop condition
        on an identical rerun.
      </p>
      <div class="study-document-actions">
        <button
          class="study-button"
          type="button"
          onclick={() => void document.rerunPilot(api)}
        >
          Rerun pilot
        </button>
      </div>
    </section>
  {/if}

  <StudyRunPicker
    open={document.finalMapping.pickerOpen}
    tier={document.finalMapping.pickerTier ?? ""}
    runs={document.finalMapping.pickerRuns}
    onOpenChange={handleFinalPickerOpenChange}
    onSelect={selectFinalRun}
  />

  {#if document.hasResults}
    <section class="study-document-section" aria-label="Analysis results">
      <Tabs.Root
        class="study-results-tabs"
        value={document.activeResultTab}
        onValueChange={selectResultTab}
      >
        <Tabs.List class="study-results-tab-list" aria-label="Study results">
          {#each resultTabs as tab (tab.value)}
            <Tabs.Trigger class="study-results-tab" value={tab.value}>
              {tab.label}
            </Tabs.Trigger>
          {/each}
        </Tabs.List>

        {#each resultTabs as tab (tab.value)}
          {@const result = resultFor(tab.value)}
          <Tabs.Content class="study-results-panel" value={tab.value}>
            {#if result}
              <div class="study-results-toolbar">
                <button
                  class="study-button"
                  type="button"
                  onclick={() => document.downloadResult(tab.value)}
                >
                  {downloadLabel(tab.value)}
                </button>
                {#if !result.downloadRequested}
                  <span class="study-results-download-hint">
                    Result ZIP download not requested.
                  </span>
                {/if}
              </div>
              <StudyAnalysis analysis={result.analysis} />
            {:else}
              <p class="study-document-note">
                {emptyResultMessage(tab.value)}
              </p>
            {/if}
          </Tabs.Content>
        {/each}
      </Tabs.Root>
    </section>
  {/if}
</article>

<style>
  .study-document {
    height: 100%;
    min-height: 0;
    overflow: auto;
    overscroll-behavior: contain;
    padding: var(--ui-space-6);
    background: var(--ui-color-surface);
    color: var(--ui-color-text);
  }

  .study-document-header {
    max-width: 62rem;
    margin-bottom: var(--ui-space-6);
  }

  h1,
  h2,
  p {
    margin: 0;
  }

  h1 {
    font-size: 1.5rem;
    line-height: 1.2;
  }

  h2 {
    margin-bottom: var(--ui-space-2);
    font-size: var(--ui-text-base);
  }

  .study-document-status {
    margin-top: var(--ui-space-2);
    color: var(--ui-color-text-secondary);
  }

  .study-document-meta {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
    gap: var(--ui-space-2) var(--ui-space-3);
    max-width: 62rem;
    margin: 0 0 var(--ui-space-6);
    font-size: var(--ui-text-sm);
  }

  .study-document-meta div {
    display: flex;
    flex-direction: column;
    gap: 0.125rem;
  }

  .study-document-meta dt {
    color: var(--ui-color-text-secondary);
  }

  .study-document-meta dd {
    margin: 0;
    overflow-wrap: anywhere;
  }

  .study-document-section {
    max-width: 62rem;
    margin-bottom: var(--ui-space-6);
  }

  .study-document-table {
    width: 100%;
    border-collapse: collapse;
    font-size: var(--ui-text-sm);
  }

  .study-document-table th,
  .study-document-table td {
    padding: 0.375rem 0.625rem;
    border-bottom: 1px solid var(--ui-color-border-soft);
    text-align: left;
  }

  .study-document-table thead th {
    color: var(--ui-color-text-secondary);
    font-weight: 400;
  }

  .study-document-phases {
    display: flex;
    flex-wrap: wrap;
    gap: var(--ui-space-2);
    margin: 0 0 var(--ui-space-3);
    padding: 0;
    list-style: none;
    font-size: var(--ui-text-sm);
  }

  .study-document-phases li {
    padding: 0.25rem 0.625rem;
    border: 1px solid var(--ui-color-border-soft);
    border-radius: var(--ui-radius-sm);
    color: var(--ui-color-text-secondary);
  }

  .study-document-phase-active {
    border-color: var(--ui-color-accent);
    color: var(--ui-color-accent);
  }

  .study-document-error {
    max-width: 62rem;
    margin-bottom: var(--ui-space-3);
    padding: var(--ui-space-2) var(--ui-space-3);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-danger-bg, var(--ui-color-warning-bg));
    color: var(--ui-color-danger-text, var(--ui-color-warning-text));
    font-size: var(--ui-text-sm);
  }

  .study-document-mapping-summary {
    margin-bottom: var(--ui-space-3);
    color: var(--ui-color-warning-text);
    font-size: var(--ui-text-sm);
    font-weight: 600;
  }

  .study-document-validation td {
    padding-top: 0;
    color: var(--ui-color-warning-text);
    font-size: var(--ui-text-sm);
  }

  .study-document-warning {
    margin-bottom: var(--ui-space-3);
    padding: var(--ui-space-2) var(--ui-space-3);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-warning-bg);
    color: var(--ui-color-warning-text);
    font-size: var(--ui-text-sm);
  }

  .study-document-note {
    margin-bottom: var(--ui-space-3);
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }

  .study-document-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--ui-space-2);
  }

  .study-button {
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-surface);
    color: inherit;
  }

  .study-confirm {
    border-color: var(--ui-color-accent);
    background: var(--ui-color-accent);
    color: var(--ui-color-paper);
  }

  :global(.study-results-tab-list) {
    display: flex;
    gap: var(--ui-space-1);
    margin-bottom: var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border-soft);
  }

  :global(.study-results-tab) {
    padding: 0.375rem 0.75rem;
    border: 0;
    border-bottom: 2px solid transparent;
    background: transparent;
    color: var(--ui-color-text-secondary);
  }

  :global(.study-results-tab[data-state="active"]) {
    border-bottom-color: var(--ui-color-accent);
    color: var(--ui-color-text);
  }

  .study-results-toolbar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--ui-space-2);
    margin-bottom: var(--ui-space-3);
  }

  .study-results-download-hint {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }

  @media (max-width: 48em) {
    .study-document {
      padding: var(--ui-space-4);
    }
  }
</style>
