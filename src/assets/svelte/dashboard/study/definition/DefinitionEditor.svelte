<script lang="ts">
  import { tick } from "svelte";
  import FieldError from "../../../ui-kit/primitives/FieldError.svelte";
  import { studyFeasibility } from "../../../contracts.generated/dashboard/study";
  import type { StudyDocument } from "../StudyDocument.svelte";
  import type { DashboardApi } from "../../dashboard-api";
  import type { GraphSummary } from "../../../contracts.generated/dashboard/graph";
  import TextInput from "../../../ui-kit/primitives/TextInput.svelte";
  import Select from "../../../ui-kit/primitives/Select.svelte";
  import OptionPickerDialog from "../../../ui-kit/composites/OptionPickerDialog.svelte";
  import TierEditor from "./TierEditor.svelte";
  import YamlView from "./YamlView.svelte";
  import { errorText } from "../StudyExecutionModel.svelte";
  let {
    document,
    api,
    summaries,
    onOpenGraph,
  }: {
    document: StudyDocument;
    api: DashboardApi;
    summaries: GraphSummary[];
    onOpenGraph: (id: string) => void;
  } = $props();
  const formId = $props.id();
  let form = $state<HTMLFormElement>();
  const model = $derived(document.definition);
  const d = $derived(model.draft);
  let picker = $state<"actions" | "rules" | null>(null);
  const feasibilityLabels: Record<
    (typeof studyFeasibility)[keyof typeof studyFeasibility],
    string
  > = {
    [studyFeasibility.required]: "Required",
    [studyFeasibility.unrestricted]: "Unrestricted",
  };
  async function freeze() {
    if (
      globalThis.confirm(
        `Freeze study ${d.name.trim() || d.study_id}, revision ${d.revision}? The saved definition is immutable.`,
      )
    ) {
      await document.freeze();
      if (model.error) {
        await tick();
        form
          ?.querySelector<HTMLElement>(
            '[aria-invalid="true"], [data-invalid="true"]',
          )
          ?.focus();
      }
    }
  }
</script>

<form
  id="study-definition-form"
  bind:this={form}
  onsubmit={(event) => {
    event.preventDefault();
    void freeze();
  }}
>
  <div class="definition-layout">
    <div class="definition-fields">
      <p>
        Supply each scientific setting explicitly. Freeze runs the authoritative
        backend checks.
      </p>
      <fieldset>
        <legend>Study</legend>
        <div class="fields">
          <TextInput
            label="Study name (optional)"
            bind:value={d.name}
            error={model.fieldError("name")}
          />
          <TextInput
            label="Revision"
            bind:value={d.revision}
            error={model.fieldError("revision")}
            inputmode="numeric"
          />
          <TextInput
            label="Master seed"
            bind:value={d.seed}
            error={model.fieldError("seed")}
            inputmode="numeric"
          />
        </div>
      </fieldset>
      <fieldset>
        <legend>Analysis</legend>
        <div class="fields">
          <TextInput
            label="Family alpha"
            bind:value={d.family_alpha}
            error={model.fieldError("family_alpha")}
            inputmode="decimal"
          />
          <TextInput
            label="Confidence level"
            bind:value={d.confidence_level}
            error={model.fieldError("confidence_level")}
            inputmode="decimal"
          />
        </div>
      </fieldset>
      <fieldset>
        <legend>Defense policy</legend>
        <Select
          label="Feasibility"
          options={Object.values(studyFeasibility).map((value) => ({
            value,
            label: feasibilityLabels[value],
          }))}
          value={d.feasibility}
          error={model.fieldError("feasibility")}
          onchange={(value) => (d.feasibility = value)}
        />
        <button
          type="button"
          data-invalid={model.fieldError("allowed_action_types")
            ? "true"
            : undefined}
          aria-describedby={model.fieldError("allowed_action_types")
            ? `${formId}-actions-error`
            : undefined}
          onclick={() => (picker = "actions")}>Choose defense actions</button
        >
        <FieldError
          id={`${formId}-actions-error`}
          error={model.fieldError("allowed_action_types")}
        />
        <p>
          Allowed actions: {d.allowed_action_types.join(", ") ||
            "Choose actions."}
        </p>
      </fieldset>
      <fieldset>
        <legend>Simulation</legend>
        <div class="fields">
          <TextInput
            label="Iterations per run"
            bind:value={d.iterations_per_run}
            error={model.fieldError("iterations_per_run")}
            inputmode="numeric"
          />
          <TextInput
            label="Maximum attempts"
            bind:value={d.max_attempts}
            error={model.fieldError("max_attempts")}
            inputmode="numeric"
          />
        </div>
        <button
          type="button"
          data-invalid={model.fieldError("rules") ? "true" : undefined}
          aria-describedby={model.fieldError("rules")
            ? `${formId}-rules-error`
            : undefined}
          onclick={() => (picker = "rules")}>Choose simulation rules</button
        >
        <FieldError
          id={`${formId}-rules-error`}
          error={model.fieldError("rules")}
        />
        <p>Rules: {d.rules.join(", ") || "Choose rules."}</p>
      </fieldset>
      {#if model.options}
        {#each d.tiers as tier, index (tier.tier)}
          <TierEditor
            {tier}
            {index}
            {model}
            options={model.options}
            {api}
            {summaries}
            {onOpenGraph}
          />
        {/each}
        <FieldError error={model.fieldError("tiers")} />
      {:else}<p role="status">Loading registered authoring options…</p>{/if}
      <fieldset>
        <legend>Pilot candidates</legend>
        {#each d.candidates as candidate, index (candidate)}
          <div class="fields candidate">
            <TextInput
              label={`Candidate ${index + 1} ID`}
              bind:value={candidate.id}
              error={model.fieldError("candidates", index, "id")}
            />
            <TextInput
              label={`Candidate ${index + 1} plans per side`}
              bind:value={candidate.plans}
              error={model.fieldError("candidates", index, "plans")}
              inputmode="numeric"
            />
            <TextInput
              label={`Candidate ${index + 1} attacks per plan`}
              bind:value={candidate.attacks}
              error={model.fieldError("candidates", index, "attacks")}
              inputmode="numeric"
            />
            <button
              type="button"
              aria-label={`Remove candidate ${index + 1}`}
              onclick={() => {
                d.candidates.splice(index, 1);
                model.error = null;
              }}>Remove</button
            >
          </div>
        {/each}
        <button
          type="button"
          onclick={() => d.candidates.push({ id: "", plans: "", attacks: "" })}
          >Add candidate</button
        >
        <FieldError error={model.fieldError("candidates")} />
        <div class="fields">
          <TextInput
            label="Extra pool plans"
            bind:value={d.extra_pool_plans}
            error={model.fieldError("extra_pool_plans")}
            inputmode="numeric"
          />
          <TextInput
            label="Extra pool attacks"
            bind:value={d.extra_pool_attacks}
            error={model.fieldError("extra_pool_attacks")}
            inputmode="numeric"
          />
          <TextInput
            label="Outer subsamples"
            bind:value={d.outer_subsamples}
            error={model.fieldError("outer_subsamples")}
            inputmode="numeric"
          />
          <TextInput
            label="Target half-width"
            bind:value={d.target_half_width}
            error={model.fieldError("target_half_width")}
            inputmode="decimal"
          />
          <TextInput
            label="Guard quantile"
            bind:value={d.guard_quantile}
            error={model.fieldError("guard_quantile")}
            inputmode="decimal"
          />
        </div>
      </fieldset>
      <section>
        <h3>Final protocol</h3>
        <p>
          Small → Medium → Large. Each tier uses an excluded warm-up and five
          measured replicas.
        </p>
        <p>
          Measurement label: {model.options?.measurement_label ??
            "Unavailable. Final collection requires a configured measurement environment."}
        </p>
      </section>
    </div>
    <YamlView
      yaml={model.yaml}
      filename={`${d.study_id || "study"}-r${d.revision || "draft"}.yaml`}
    />
  </div>
  <div class="form-feedback" role="status">
    {#if model.formError}<pre>{errorText(
          model.formError,
        )}</pre>{:else if model.error}<p>Review the highlighted fields.</p>{/if}
    <button
      type="submit"
      disabled={model.freezing || !d.study_id || !d.family_id}
      >{model.freezing ? "Freezing…" : "Freeze revision"}</button
    >
  </div>
</form>
{#if model.options}
  <OptionPickerDialog
    open={picker !== null}
    onOpenChange={(open) => {
      if (!open) picker = null;
    }}
    items={picker === "actions" ? model.options.actions : model.options.rules}
    title={picker === "actions" ? "Defense actions" : "Simulation rules"}
    mode="multiple"
    initialSelection={picker === "actions" ? d.allowed_action_types : d.rules}
    getKey={(value) => value}
    columns={[
      {
        key: "value",
        header: "Registered value",
        getValue: (value) => value,
        filterable: true,
      },
    ]}
    emptyMessage="No registered values."
    onConfirm={(values) => {
      if (picker === "actions")
        d.allowed_action_types = values as typeof d.allowed_action_types;
      else d.rules = values as typeof d.rules;
      return true;
    }}
  />
{/if}

<style>
  .definition-layout {
    display: grid;
    grid-template-columns: minmax(20rem, 3fr) minmax(16rem, 2fr);
    gap: var(--ui-space-4);
    align-items: start;
  }
  .definition-fields {
    display: grid;
    gap: var(--ui-space-4);
    min-width: 0;
  }
  fieldset {
    border: 1px solid var(--ui-color-border);
    display: grid;
    gap: var(--ui-space-3);
    min-width: 0;
    padding: var(--ui-space-3);
  }
  legend,
  h3 {
    font-weight: 600;
    font-size: var(--ui-text-sm);
  }
  .fields {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
    gap: var(--ui-space-3);
  }
  p {
    margin: 0;
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }
  .form-feedback {
    display: grid;
    gap: var(--ui-space-3);
    padding-block: var(--ui-space-4);
  }
  pre {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  @media (max-width: 70rem) {
    .definition-layout {
      grid-template-columns: 1fr;
    }
  }
</style>
