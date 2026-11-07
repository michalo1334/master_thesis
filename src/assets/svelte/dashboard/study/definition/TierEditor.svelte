<script lang="ts">
  import type { StudyDefinitionModel } from "../StudyDefinitionModel.svelte";
  import FieldError from "../../../ui-kit/primitives/FieldError.svelte";
  import type { DefinitionOptions } from "../../../contracts.generated/dashboard/study";
  import type { GraphSummary } from "../../../contracts.generated/dashboard/graph";
  import type { DashboardApi } from "../../dashboard-api";
  import type { DraftTier } from "../types";
  import TextInput from "../../../ui-kit/primitives/TextInput.svelte";
  import Select from "../../../ui-kit/primitives/Select.svelte";
  import GraphTreePickerDialog from "../../workspace/GraphTreePickerDialog.svelte";
  import FootholdPicker from "./FootholdPicker.svelte";
  let {
    tier,
    index: tierIndex,
    model,
    options,
    api,
    summaries,
    onOpenGraph,
  }: {
    tier: DraftTier;
    index: number;
    model: StudyDefinitionModel;
    options: DefinitionOptions;
    api: DashboardApi;
    summaries: GraphSummary[];
    onOpenGraph: (id: string) => void;
  } = $props();
  const id = $props.id();
  let pickerOpen = $state(false);
  function fieldError(...path: (string | number)[]) {
    return model.fieldError("tiers", tierIndex, ...path);
  }
  function requiresScoring(strategy: string): boolean {
    return (
      options.alternatives.find((a) => a.value === strategy)
        ?.scoring_required ?? false
    );
  }
</script>

<fieldset class="tier-editor">
  <legend>{tier.tier}</legend>
  <div class="row">
    <button
      type="button"
      data-invalid={fieldError("graph_revision_id") ? "true" : undefined}
      aria-describedby={fieldError("graph_revision_id")
        ? `${id}-graph-error`
        : undefined}
      onclick={() => (pickerOpen = true)}
      >Choose {tier.tier} graph revision</button
    >
    <span
      >{summaries.find((s) => s.revision_id === tier.graph_revision_id)
        ?.title ??
        (tier.graph_revision_id || "No revision selected")}</span
    >
    {#if tier.graph_revision_id}<button
        type="button"
        onclick={() => onOpenGraph(tier.graph_revision_id)}>Open graph</button
      >{/if}
  </div>
  <FieldError
    id={`${id}-graph-error`}
    error={fieldError("graph_revision_id")}
  />
  <p class="revision">
    Revision: {tier.graph_revision_id || "Choose a saved revision."}
  </p>
  {#key tier.graph_revision_id}
    <FootholdPicker
      revisionId={tier.graph_revision_id}
      label={`${tier.tier} foothold Host`}
      value={tier.foothold_node_id}
      error={fieldError("foothold_node_id")}
      {api}
      onchange={(value) => (tier.foothold_node_id = value)}
    />
  {/key}
  <div class="row budgets">
    {#each tier.budgets as budget, index (index)}
      <div>
        <TextInput
          label={`${tier.tier} budget ${index + 1}`}
          value={budget}
          error={fieldError("budgets", index)}
          inputmode="numeric"
          onchange={(value) => (tier.budgets[index] = value)}
        />
        <button
          type="button"
          aria-label={`Remove ${tier.tier} budget ${index + 1}`}
          onclick={() => {
            tier.budgets.splice(index, 1);
            model.error = null;
          }}>Remove</button
        >
      </div>
    {/each}
    <button type="button" onclick={() => tier.budgets.push("")}
      >Add budget</button
    >
  </div>
  <FieldError error={fieldError("budgets")} />
  <p>Reference: CVSS at each declared budget.</p>
  {#each tier.alternatives as alternative, index (alternative)}
    <div class="row alternative">
      <Select
        label={`${tier.tier} alternative ${index + 1}`}
        options={options.alternatives.map((a) => ({
          value: a.value,
          label: a.value,
        }))}
        value={alternative.strategy}
        error={fieldError("alternatives", index, "strategy")}
        onchange={(value) => {
          alternative.strategy = value;
          alternative.objective = "";
          alternative.monte_carlo_trials = "";
        }}
      />
      {#if requiresScoring(alternative.strategy)}
        <Select
          label={`${tier.tier} scoring objective ${index + 1}`}
          options={options.objectives.map((value) => ({ value, label: value }))}
          value={alternative.objective}
          error={fieldError("alternatives", index, "objective")}
          onchange={(value) => (alternative.objective = value)}
        />
        <TextInput
          label={`${tier.tier} scoring trials ${index + 1}`}
          bind:value={alternative.monte_carlo_trials}
          error={fieldError("alternatives", index, "monte_carlo_trials")}
          inputmode="numeric"
        />
      {/if}
      <button
        type="button"
        aria-label={`Remove ${tier.tier} alternative ${index + 1}`}
        onclick={() => {
          tier.alternatives.splice(index, 1);
          model.error = null;
        }}>Remove</button
      >
    </div>
  {/each}
  <button
    type="button"
    onclick={() =>
      tier.alternatives.push({
        strategy: "",
        objective: "",
        monte_carlo_trials: "",
      })}>Add {tier.tier} alternative</button
  >
  <FieldError error={fieldError("alternatives")} />
</fieldset>
<GraphTreePickerDialog
  open={pickerOpen}
  onOpenChange={(value) => (pickerOpen = value)}
  {summaries}
  title={`Choose ${tier.tier} graph revision`}
  description="Select a saved revision. Its Hosts constrain the foothold choices."
  selectedRevisionId={tier.graph_revision_id}
  onSelect={(summary) => {
    tier.graph_revision_id = summary.revision_id;
    tier.foothold_node_id = "";
    return true;
  }}
  onFavoriteChange={async (summary, favorite) =>
    (await api.setGraphRevisionFavorite(summary.revision_id, favorite))
      .status === "ok"}
/>

<style>
  .tier-editor {
    min-width: 0;
    border: 1px solid var(--ui-color-border);
    padding: var(--ui-space-3);
    display: grid;
    gap: var(--ui-space-3);
  }
  legend {
    text-transform: capitalize;
    font-weight: 600;
  }
  .row {
    display: flex;
    flex-wrap: wrap;
    align-items: end;
    gap: var(--ui-space-3);
  }
  .budgets > div {
    max-width: 12rem;
  }
  .revision {
    overflow-wrap: anywhere;
    font-size: var(--ui-text-sm);
    color: var(--ui-color-text-secondary);
  }
  p {
    margin: 0;
  }
</style>
