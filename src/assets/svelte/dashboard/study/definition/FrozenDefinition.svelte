<script lang="ts">
  import type { StudyDocument } from "../StudyDocument.svelte";
  import FilterableTable from "../../../ui-kit/composites/FilterableTable.svelte";
  import { StudyDefinitionModel } from "../StudyDefinitionModel.svelte";
  import YamlView from "./YamlView.svelte";
  let { document }: { document: StudyDocument } = $props();
  const detail = $derived(document.detail);
  const yaml = $derived(
    detail ? new StudyDefinitionModel(detail.authored).yaml : "",
  );
</script>

{#if detail}
  {@const d = detail.authored}
  <section class="frozen-definition" aria-label="Frozen study definition">
    <div class="facts">
      <p>
        <strong>Study:</strong>
        {d.name || d.study_id} · Revision {d.revision}
      </p>
      {#if d.name}<p><strong>Study ID:</strong> {d.study_id}</p>{/if}
      <p><strong>Master seed:</strong> {d.seed}</p>
      <p>
        <strong>Family:</strong>
        {d.family_id} · α {d.family_alpha} · Confidence {d.confidence_level}
      </p>
      <p>
        <strong>Measurement label:</strong>
        {String(detail.context.measurement_label ?? "Unavailable")}
      </p>
    </div>
    <div class="tier-table">
      <FilterableTable
        items={d.tiers}
        getKey={(t) => t.tier}
        columns={[
          { key: "tier", header: "Tier", getValue: (t) => t.tier },
          {
            key: "graph",
            header: "Graph revision",
            getValue: (t) => t.graph_revision_id,
          },
          {
            key: "host",
            header: "Foothold Host",
            getValue: (t) => t.foothold_node_id,
          },
          {
            key: "budgets",
            header: "Budgets",
            getValue: (t) => t.budgets.join(", "),
          },
          {
            key: "alternatives",
            header: "Alternatives",
            getValue: (t) =>
              t.alternatives
                .map(
                  (a) =>
                    `${a.strategy}${a.objective ? ` (${a.objective}, ${a.monte_carlo_trials} trials)` : ""}`,
                )
                .join("; "),
          },
        ]}
        emptyMessage="No tiers."
        noMatchMessage="No matching tiers."
      />
    </div>
    <details>
      <summary>Defense and simulation settings</summary>
      <p>
        Feasibility: {d.feasibility}. Actions: {d.allowed_action_types.join(
          ", ",
        )}.
      </p>
      <p>
        Iterations per run: {d.iterations_per_run}. Maximum attempts: {d.max_attempts}.
      </p>
      <p>Rules: {d.rules.join(", ")}.</p>
    </details>
    <details>
      <summary>Pilot candidates and precision settings</summary>
      <FilterableTable
        items={d.candidates}
        getKey={(c) => c.id}
        columns={[
          { key: "id", header: "Candidate", getValue: (c) => c.id },
          {
            key: "plans",
            header: "Plans per side",
            getValue: (c) => String(c.plans),
          },
          {
            key: "attacks",
            header: "Attacks per plan",
            getValue: (c) => String(c.attacks),
          },
        ]}
        emptyMessage="No candidates."
        noMatchMessage="No matching candidates."
      />
      <p>
        Extra pool: {d.extra_pool_plans} plans and {d.extra_pool_attacks} attacks.
      </p>
      <p>
        Outer subsamples: {d.outer_subsamples}. Target half-width: {d.target_half_width}.
        Guard quantile: {d.guard_quantile}.
      </p>
    </details>
    <details>
      <summary>Derived structure and frozen context</summary>
      <dl>
        {#each Object.entries(detail.structure) as [key, value] (key)}<dt>
            {key.replaceAll("_", " ")}
          </dt>
          <dd>{String(value)}</dd>{/each}
      </dl>
      <pre>{JSON.stringify(detail.context, null, 2)}</pre>
    </details>
    <details>
      <summary>Generated YAML</summary><YamlView
        {yaml}
        filename={`${d.study_id}-r${d.revision}.yaml`}
      />
    </details>
  </section>
{:else}<p role="status">Loading frozen definition…</p>{/if}

<style>
  .frozen-definition {
    display: grid;
    gap: var(--ui-space-4);
  }
  .facts {
    display: flex;
    gap: var(--ui-space-4);
    flex-wrap: wrap;
  }
  .tier-table {
    min-height: 14rem;
    overflow: auto;
  }
  details {
    border: 1px solid var(--ui-color-border);
    padding: var(--ui-space-3);
  }
  summary {
    font-weight: 600;
    cursor: pointer;
  }
  pre {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  dl {
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: var(--ui-space-2);
  }
</style>
