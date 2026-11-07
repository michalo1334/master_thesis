<script lang="ts">
  import {
    studyOutcomes,
    studyStates,
  } from "../../../contracts.generated/dashboard/study";
  import type { StudyExecutionModel } from "../StudyExecutionModel.svelte";
  import FilterableTable from "../../../ui-kit/composites/FilterableTable.svelte";
  import Select from "../../../ui-kit/primitives/Select.svelte";
  import Checkbox from "../../../ui-kit/primitives/Checkbox.svelte";
  let { model }: { model: StudyExecutionModel } = $props();
  const pilot = $derived(model.pilot);
  const candidate = $derived(
    pilot?.candidates.find((c) => c.id === model.presentation.pilotCandidateId),
  );
  const format = (n: number | null | undefined) =>
    n == null ? "Unavailable" : n.toPrecision(7);
</script>

{#if pilot}
  <section aria-label="Pilot report" class="pilot-review">
    <h3>Outcome: {pilot.outcome.outcome}</h3>
    <p>Method: {pilot.method}. Selection rule: {pilot.selection_rule}.</p>
    <div class="candidate-table">
      <FilterableTable
        items={pilot.candidates}
        getKey={(c) => c.id}
        columns={[
          {
            key: "id",
            header: "Candidate",
            getValue: (c) => c.id,
            filterable: true,
          },
          {
            key: "plans",
            header: "Plans per side",
            getValue: (c) => String(c.plan_count_per_side),
          },
          {
            key: "attacks",
            header: "Attacks per plan",
            getValue: (c) => String(c.attacks_per_plan),
          },
          {
            key: "runtime",
            header: "Predicted time (ms)",
            getValue: (c) => format(c.predicted_runtime_ms),
          },
          {
            key: "precision",
            header: "Worst guarded half-width",
            getValue: (c) => format(c.worst_guarded_half_width),
          },
          {
            key: "pass",
            header: "Pass",
            getValue: (c) => (c.passes ? "Yes" : "No"),
          },
        ]}
        selectionMode="single"
        bind:selectedKeys={
          () =>
            model.presentation.pilotCandidateId
              ? [model.presentation.pilotCandidateId]
              : [],
          (keys) => (model.presentation.pilotCandidateId = keys[0] ?? "")
        }
        emptyMessage="No candidate report."
        noMatchMessage="No matching candidates."
      />
    </div>
    {#if candidate}
      <h4>Candidate {candidate.id} · comparison assessments</h4>
      <div class="comparison-table">
        <FilterableTable
          items={candidate.comparisons}
          getKey={(c) => JSON.stringify(c.identity)}
          columns={[
            {
              key: "tier",
              header: "Tier",
              getValue: (c) => c.identity.tier,
              filterable: true,
            },
            {
              key: "budget",
              header: "Budget",
              getValue: (c) => String(c.identity.budget),
            },
            {
              key: "alternative",
              header: "Alternative vs CVSS",
              getValue: (c) => c.identity.alternative,
              filterable: true,
            },
            {
              key: "width",
              header: "Guarded half-width",
              getValue: (c) => format(c.guarded_half_width),
            },
            {
              key: "informative",
              header: "Informative",
              getValue: (c) => (c.informative ? "Yes" : "No"),
            },
            {
              key: "pass",
              header: "Pass",
              getValue: (c) => (c.passes ? "Yes" : "No"),
            },
          ]}
          emptyMessage="No comparison assessments."
          noMatchMessage="No matching assessments."
        />
      </div>
    {/if}
    {#if model.status?.state === studyStates.awaiting_final}
      <section class="approval" aria-label="Final approval">
        {#if pilot.outcome.outcome === studyOutcomes.recommended}
          <p>
            Recommended candidate: {pilot.outcome.candidate_id}. Approval
            freezes {pilot.outcome.plan_count_per_side} plans per side and {pilot
              .outcome.attacks_per_plan} attacks per plan.
          </p>
          <button
            id="study-approve-recommended"
            type="button"
            disabled={model.commandPending}
            onclick={() => void model.approve()}
            >Approve recommended candidate</button
          >
        {:else if pilot.outcome.outcome === studyOutcomes.insufficient}
          <p>
            No candidate met the Pilot precision target. An override requires a
            declared candidate and explicit confirmation.
          </p>
          <Select
            label="Insufficient override candidate"
            options={pilot.candidates.map((c) => ({
              value: c.id,
              label: `${c.id} · ${c.plan_count_per_side} × ${c.attacks_per_plan}`,
            }))}
            value={model.candidateId}
            onchange={(value) => {
              model.candidateId = value;
              model.overrideConfirmed = false;
            }}
          />
          <Checkbox
            label="I accept proceeding without meeting the Pilot precision target."
            bind:checked={model.overrideConfirmed}
          />
          <button
            id="study-approve-override"
            type="button"
            disabled={model.commandPending || !model.overrideConfirmed}
            onclick={() => void model.approve()}
            >Approve insufficient override</button
          >
        {/if}
      </section>
    {/if}
    <p>Pilot precision supports planning. Fresh Final precision can differ.</p>
  </section>
{:else}<p role="status">
    The accepted Pilot report is unavailable in the current lifecycle state.
  </p>{/if}

<style>
  .pilot-review {
    display: grid;
    gap: var(--ui-space-3);
  }
  h3,
  h4,
  p {
    margin: 0;
  }
  .candidate-table,
  .comparison-table {
    min-height: 15rem;
    overflow: auto;
  }
  .approval {
    border: 1px solid var(--ui-color-accent);
    padding: var(--ui-space-3);
    display: grid;
    gap: var(--ui-space-3);
  }
</style>
