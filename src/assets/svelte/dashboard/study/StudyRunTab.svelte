<script lang="ts">
  import { formatTimestamp } from "../format";
  import type { StudyModel } from "./StudyModel.svelte";
  import { formatStudyRunError } from "./study-types";

  interface Props {
    model: StudyModel;
  }

  let { model }: Props = $props();
</script>

<section class="study-run" aria-label="Tier mapping">
  {#if !model.isSavedVersion}
    <p class="study-run-notice">
      Save an immutable specification version to map declared tiers.
    </p>
  {:else if model.isLoadingRuns}
    <p class="study-run-notice" role="status">Loading completed runs…</p>
  {:else if !model.hasEligibleRuns}
    <div class="study-run-empty">
      <p>
        No completed non-warm-up evaluation run qualifies. Complete an
        evaluation run first, then map it to each declared tier.
      </p>
      <button
        class="study-button"
        type="button"
        onclick={() => model.openEvaluationManifest()}
      >
        Open evaluation manifest
      </button>
    </div>
  {:else}
    <p class="study-run-summary" role="status">
      {model.savedVersionLabel} · {model.mappedCount} of {model.declaredTiers
        .length} tiers mapped
    </p>

    <div class="study-run-table-wrap">
      <table class="study-run-table">
        <thead>
          <tr>
            <th scope="col">Tier</th>
            <th scope="col">Required inputs</th>
            <th scope="col">Run</th>
            <th scope="col">Graph</th>
            <th scope="col">Completed</th>
            <th scope="col">Plans / trials</th>
            <th scope="col"
              ><span class="study-visually-hidden">Action</span></th
            >
          </tr>
        </thead>
        <tbody>
          {#each model.declaredTiers as tier (tier)}
            {@const run = model.runFor(tier)}
            <tr>
              <th scope="row">{tier}</th>
              <td class="study-run-required" title={model.required_inputs}>
                {model.required_inputs || "—"}
              </td>
              <td>{run?.manifest_title ?? "Not selected"}</td>
              <td>{run?.graph_title ?? "—"}</td>
              <td>
                {run?.completed_at ? formatTimestamp(run.completed_at) : "—"}
              </td>
              <td>
                {run ? `${run.plan_count} / ${run.trial_count}` : "—"}
              </td>
              <td class="study-run-action">
                <button
                  class="study-button"
                  type="button"
                  aria-label={`${run ? "Change" : "Choose"} run for tier ${tier}`}
                  onclick={() => model.openRunPicker(tier)}
                >
                  {run ? "Change" : "Choose"}
                </button>
                {#if run}
                  <button
                    class="study-button"
                    type="button"
                    aria-label={`Clear run for tier ${tier}`}
                    onclick={() => model.clearRun(tier)}
                  >
                    Clear
                  </button>
                {/if}
              </td>
            </tr>
            {#if model.missingSelectionMessage(tier)}
              <tr class="study-run-validation">
                <td colspan="7">{model.missingSelectionMessage(tier)}</td>
              </tr>
            {/if}
          {/each}
        </tbody>
      </table>
    </div>

    {#if model.hasMissingSelections}
      <p class="study-run-mapping-summary" role="alert">
        Select one completed run for every declared tier.
      </p>
    {/if}

    {#if model.preflightStatus === "loading"}
      <p class="study-run-notice" role="status">Checking the study bundle…</p>
    {:else if model.preflightStatus === "ok"}
      <p class="study-run-ok" role="status">Preflight passed.</p>
    {:else if model.preflightStatus === "rejected" && model.visiblePreflightErrors.length > 0}
      <ul class="study-run-errors" role="alert">
        {#each model.visiblePreflightErrors as error (error.code)}
          <li>{formatStudyRunError(error)}</li>
        {/each}
      </ul>
    {/if}

    <div class="study-run-actions">
      <button
        class="study-button study-confirm"
        type="button"
        disabled={!model.canStartPilot}
        onclick={() => void model.runPilot()}
      >
        Run pilot
      </button>
    </div>
  {/if}
</section>

<style>
  .study-run {
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-3);
    min-height: 0;
    overflow: auto;
  }

  .study-run-notice,
  .study-run-ok,
  .study-run-empty p {
    margin: 0;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-surface);
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }

  .study-run-ok {
    background: color-mix(in srgb, var(--ui-color-accent) 12%, transparent);
    color: inherit;
  }

  .study-run-empty {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--ui-space-2);
  }

  .study-run-summary {
    margin: 0;
    font-size: var(--ui-text-sm);
    color: var(--ui-color-text-secondary);
  }

  .study-run-table-wrap {
    min-height: 0;
    overflow: auto;
    border: 1px solid var(--ui-color-border-soft);
    border-radius: var(--ui-radius-md);
  }

  .study-run-table {
    width: 100%;
    border-collapse: collapse;
    font-size: var(--ui-text-sm);
  }

  .study-run-table th,
  .study-run-table td {
    padding: 0.375rem 0.625rem;
    border-bottom: 1px solid var(--ui-color-border-soft);
    text-align: left;
    vertical-align: middle;
  }

  .study-run-table thead th {
    color: var(--ui-color-text-secondary);
    font-weight: 400;
  }

  .study-run-table tbody tr:last-child td,
  .study-run-table tbody tr:last-child th {
    border-bottom: 0;
  }

  .study-run-action {
    display: flex;
    gap: var(--ui-space-1);
  }

  .study-run-required {
    max-width: 22rem;
    color: var(--ui-color-text-secondary);
    overflow-wrap: anywhere;
  }

  .study-run-validation td {
    padding-top: 0;
    color: var(--ui-color-warning-text);
  }

  .study-run-mapping-summary,
  .study-run-errors {
    margin: 0;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-danger-bg, var(--ui-color-warning-bg));
    color: var(--ui-color-danger-text, var(--ui-color-warning-text));
    font-size: var(--ui-text-sm);
    list-style: none;
  }

  .study-run-mapping-summary {
    margin: 0;
    color: var(--ui-color-warning-text);
    font-size: var(--ui-text-sm);
    font-weight: 600;
  }

  .study-run-actions {
    display: flex;
    justify-content: flex-end;
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

  .study-button:disabled {
    cursor: default;
    opacity: 0.55;
  }

  .study-visually-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
</style>
