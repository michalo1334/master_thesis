<script lang="ts">
  import { Tabs } from "bits-ui";
  import {
    studyPhases,
    studyProgression,
    studyStates,
  } from "../../../contracts.generated/dashboard/study";
  import type { StudyDocument } from "../StudyDocument.svelte";
  import {
    errorText,
    type StudyExecutionModel,
  } from "../StudyExecutionModel.svelte";
  import ReportProgress from "../../ReportProgress.svelte";
  import PilotReview from "../pilot/PilotReview.svelte";
  import FinalResults from "../results/FinalResults.svelte";
  let {
    model,
    document,
  }: { model: StudyExecutionModel; document: StudyDocument } = $props();
  const labels: Record<(typeof studyProgression)[number], string> = {
    [studyStates.collecting_pilot]: "Pilot collection",
    [studyStates.analyzing_pilot]: "Pilot analysis",
    [studyStates.awaiting_final]: "Approval",
    [studyStates.collecting_final]: "Final collection",
    [studyStates.analyzing_final]: "Final analysis",
    [studyStates.succeeded]: "Complete",
  };
  const stages = studyProgression.map((state) => ({
    state,
    label: labels[state],
  }));
  const active = $derived(
    stages.findIndex((s) => s.state === model.status?.state),
  );
  async function cancel() {
    if (globalThis.confirm("Cancel this study execution?"))
      await model.cancel();
  }
</script>

<section class="execution-view" aria-label="Selected study execution">
  <header>
    <h3>Execution {model.executionId}</h3>
    <strong
      >{model.status?.state.replaceAll("_", " ") ??
        "Loading accepted state…"}</strong
    >
  </header>
  {#if model.notice}<div class="notice" role="status" aria-live="polite">
      {model.notice}
    </div>{/if}
  {#if model.status?.error}<pre class="failure" role="alert">{errorText(
        model.status.error,
      )}</pre>{/if}
  {#if model.error}<pre class="failure" role="alert">{errorText(
        model.error,
      )}</pre>{/if}
  <Tabs.Root bind:value={model.view}>
    <Tabs.List aria-label="Execution sections"
      ><Tabs.Trigger value="status">Status</Tabs.Trigger><Tabs.Trigger
        value="pilot">Pilot</Tabs.Trigger
      ><Tabs.Trigger value="results"
        >Results{model.result ? "" : ": unavailable"}</Tabs.Trigger
      ></Tabs.List
    >
    <Tabs.Content value="status">
      <ol class="steps" aria-label="Execution stages">
        {#each stages as stage, index (stage.state)}<li
            aria-current={active === index ? "step" : undefined}
            class={{ done: active > index }}
          >
            {active > index
              ? "✓ "
              : active === index
                ? "● "
                : "○ "}{stage.label}
          </li>{/each}
      </ol>
      {#if model.status?.selection}<p>
          Frozen selection: {model.status.selection.candidate_id} · {model
            .status.selection.plan_count_per_side} plans per side · {model
            .status.selection.attacks_per_plan} attacks per plan.
        </p>{/if}
      {#if model.progress}
        <p>
          Phase: {model.progress.phase ?? "No active phase"} · Tier: {model
            .progress.tier ?? "All Pilot tiers / unavailable"} · {model.progress
            .warm_up
            ? "Warm-up (excluded)"
            : model.progress.replica != null &&
                model.progress.phase === studyPhases.final_collection
              ? `Measured replica ${model.progress.replica + 1} of 5`
              : "Pilot / analysis scope"}
        </p>
        <div class="counters" aria-live="off">
          {#each model.progress.counters as counter (counter.unit)}
            <div>
              <ReportProgress
                progress={counter.total != null
                  ? { completed: counter.completed, total: counter.total }
                  : null}
                label={counter.unit.replaceAll("_", " ")}
                waitingMessage={`Waiting for ${counter.unit.replaceAll("_", " ")} totals…`}
              />
            </div>
          {/each}
        </div>
        {#if model.progress.activity}<p>
            Activity: {model.progress.activity}
          </p>{/if}
      {/if}
      <p>
        Progress counters use their named units. Measured timing comes from
        accepted duration receipts.
      </p>
      <div class="actions">
        <button
          class="dashboard-action-button"
          id="study-continue"
          type="button"
          disabled={!model.canContinue}
          onclick={() => void model.continue()}
          >{model.pendingRequestId ? "Continue pending…" : "Continue"}</button
        >
        <button
          class="dashboard-action-button"
          type="button"
          onclick={() => void model.refresh()}>Refresh status</button
        >
        <button
          class="dashboard-action-button"
          type="button"
          disabled={!model.canCancel}
          onclick={() => void cancel()}>Cancel execution</button
        >
      </div>
      {#if model.pendingRequestId}<p role="status">
          Continuation request active. Switching tabs preserves this request.
        </p>{/if}
      {#if model.lifecycle?.restartable}<div class="actions">
          <button
            class="dashboard-action-button"
            type="button"
            onclick={() => (document.tab = "definition")}
            >View definition</button
          ><button
            class="dashboard-action-button"
            type="button"
            disabled={document.starting || document.startUncertain}
            onclick={() => void document.start()}>Start new execution</button
          >
        </div>{/if}
    </Tabs.Content>
    <Tabs.Content value="pilot"
      ><PilotReview {model} />
      {#if model.canCancel}<button
          class="dashboard-action-button"
          type="button"
          onclick={() => void cancel()}>Cancel execution</button
        >{/if}
    </Tabs.Content>
    <Tabs.Content value="results"><FinalResults {model} /></Tabs.Content>
  </Tabs.Root>
</section>

<style>
  .execution-view {
    display: grid;
    gap: var(--ui-space-3);
  }
  header,
  .actions {
    display: flex;
    gap: var(--ui-space-3);
    align-items: center;
    flex-wrap: wrap;
  }
  header h3 {
    margin: 0;
    overflow-wrap: anywhere;
  }
  .notice {
    border: 1px solid var(--ui-color-accent);
    padding: var(--ui-space-3);
    background: var(--ui-color-paper);
  }
  .failure {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    border: 1px solid var(--ui-color-border);
    padding: var(--ui-space-3);
  }
  .steps {
    display: flex;
    list-style: none;
    padding: 0;
    gap: var(--ui-space-3);
    flex-wrap: wrap;
    color: var(--ui-color-text-secondary);
  }
  .steps [aria-current="step"] {
    font-weight: 700;
    color: var(--ui-color-accent);
  }
  .steps .done {
    color: var(--ui-color-text);
  }
  .counters {
    display: flex;
    gap: var(--ui-space-4);
    flex-wrap: wrap;
    margin-block: var(--ui-space-4);
  }
</style>
