<script lang="ts">
  import { Tabs } from "bits-ui";
  import { onMount } from "svelte";
  import { errorText } from "../StudyExecutionModel.svelte";
  import type { StudyExecutionModel } from "../StudyExecutionModel.svelte";
  import FilterableTable from "../../../ui-kit/composites/FilterableTable.svelte";
  import Select from "../../../ui-kit/primitives/Select.svelte";
  let { model }: { model: StudyExecutionModel } = $props();
  const view = $derived(model.presentation);
  onMount(() => {
    void model.readResult();
  });
  const result = $derived(model.result);
  const comparisons = $derived(model.filteredComparisons);
  const comparison = $derived(model.selectedComparison);
  const timing = $derived(
    result?.timing.find((t) => t.tier === view.timingTier),
  );
  const format = (n: number) =>
    Number.isFinite(n) ? n.toPrecision(7) : String(n);
  const duration = (n: number) =>
    `${format(n / (view.unit === "s" ? 1_000_000 : view.unit === "ms" ? 1_000 : 1))} ${view.unit}`;
  const choices = (values: string[]) => [
    { value: "all", label: "All" },
    ...Array.from(new Set(values)).map((value) => ({ value, label: value })),
  ];
</script>

{#if result}
  <section aria-label="Stored Final result" class="final-results">
    <h3>Stored Final result</h3>
    <p>
      Candidate: {result.selection.candidate_id} · {result.selection
        .plan_count_per_side} plans per side · {result.selection
        .attacks_per_plan} attacks per plan.
    </p>
    <p>
      Pilot outcome: {result.pilot_outcome.outcome}. Family: {result.family_id}.
      Method: {result.family_method}, α {result.family_alpha}.
    </p>
    <Tabs.Root bind:value={view.resultTab}>
      <Tabs.List aria-label="Final result sections"
        ><Tabs.Trigger value="comparisons">Comparisons</Tabs.Trigger
        ><Tabs.Trigger value="timing">Timing</Tabs.Trigger></Tabs.List
      >
      <Tabs.Content value="comparisons">
        <div class="filters">
          <Select
            label="Result tier"
            options={choices(result.comparisons.map((c) => c.identity.tier))}
            bind:value={view.tier}
          />
          <Select
            label="Result budget"
            options={choices(
              result.comparisons.map((c) => String(c.identity.budget)),
            )}
            bind:value={view.budget}
          />
          <Select
            label="Result alternative"
            options={choices(
              result.comparisons.map((c) => c.identity.alternative),
            )}
            bind:value={view.alternative}
          />
        </div>
        <div class="result-table">
          <FilterableTable
            items={comparisons}
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
                header: "Alternative",
                getValue: (c) => c.identity.alternative,
                filterable: true,
              },
              {
                key: "estimate",
                header: "Estimate",
                getValue: (c) => format(c.estimate),
              },
              {
                key: "interval",
                header: "Pointwise interval",
                getValue: (c) => `[${format(c.lower)}, ${format(c.upper)}]`,
              },
              {
                key: "raw",
                header: "Raw p",
                getValue: (c) => format(c.raw_p_value),
              },
              {
                key: "holm",
                header: "Holm p",
                getValue: (c) => format(c.adjusted_p_value),
              },
              {
                key: "reject",
                header: "Reject",
                getValue: (c) => (c.reject_null ? "Yes" : "No"),
              },
            ]}
            selectionMode="single"
            bind:selectedKeys={
              () => (view.selectedComparison ? [view.selectedComparison] : []),
              (keys) => (view.selectedComparison = keys[0] ?? "")
            }
            emptyMessage="No comparisons for these filters."
            noMatchMessage="No matching comparisons."
          />
        </div>
        {#if comparison}<section
            class="selected-comparison"
            aria-label="Selected comparison"
          >
            <h4>
              {comparison.identity.tier} · Budget {comparison.identity.budget} · {comparison
                .identity.alternative} vs {comparison.identity.reference}
            </h4>
            <p>
              Contrast: {comparison.contrast}. Estimate: {format(
                comparison.estimate,
              )}. Confidence: {comparison.confidence_level}. Pointwise interval:
              [{format(comparison.lower)}, {format(comparison.upper)}].
            </p>
            <p>
              Statistics: {comparison.method}. Test: {comparison.test_method}, {comparison.test_alternative}.
            </p>
            <p>
              Raw p: {format(comparison.raw_p_value)}. Holm p: {format(
                comparison.adjusted_p_value,
              )}. Family decision: {comparison.reject_null
                ? "Reject null"
                : "Retain null"}.
            </p>
            <p>
              Assessment: {comparison.assessment}. Warnings: {comparison.warnings.join(
                ", ",
              ) || "None"}.
            </p>
          </section>{/if}
        <p>
          Negative mission-impact differences favor the alternative. Family
          decisions use Holm-adjusted p-values. Intervals remain pointwise.
        </p>
      </Tabs.Content>
      <Tabs.Content value="timing">
        <div class="filters">
          <Select
            label="Timing tier"
            options={result.timing.map((t) => ({
              value: t.tier,
              label: t.tier,
            }))}
            bind:value={view.timingTier}
          />
          <Select
            label="Display units"
            options={[
              { value: "s", label: "Seconds" },
              { value: "ms", label: "Milliseconds" },
              { value: "μs", label: "Microseconds" },
            ]}
            bind:value={view.unit}
          />
        </div>
        {#if timing}
          {#key view.unit}
            <h4>Measured duration summaries</h4>
            <div class="timing-table">
              <FilterableTable
                items={timing.summaries}
                getKey={(s) => s.boundary}
                columns={[
                  {
                    key: "boundary",
                    header: "Boundary",
                    getValue: (s) => s.boundary.replaceAll("_", " "),
                  },
                  {
                    key: "median",
                    header: "Median",
                    getValue: (s) => duration(s.median_us),
                  },
                  {
                    key: "min",
                    header: "Minimum",
                    getValue: (s) => duration(s.minimum_us),
                  },
                  {
                    key: "max",
                    header: "Maximum",
                    getValue: (s) => duration(s.maximum_us),
                  },
                ]}
                emptyMessage="No timing summaries."
                noMatchMessage="No matching summaries."
              />
            </div>
            <h4>Five measured replicas</h4>
            <div class="timing-table">
              <FilterableTable
                items={timing.replicas}
                getKey={(r) => String(r.position)}
                columns={[
                  {
                    key: "replica",
                    header: "Replica",
                    getValue: (r) => String(r.position + 1),
                  },
                  {
                    key: "selection",
                    header: "Plan selection",
                    getValue: (r) => duration(r.plan_selection_us),
                  },
                  {
                    key: "simulation",
                    header: "Simulation",
                    getValue: (r) => duration(r.simulation_us),
                  },
                  {
                    key: "total",
                    header: "Total",
                    getValue: (r) => duration(r.total_us),
                  },
                ]}
                emptyMessage="No measured replicas."
                noMatchMessage="No matching replicas."
              />
            </div>
          {/key}
        {/if}
        <p>
          Warm-up is excluded. Total covers measured plan selection and
          simulation. Later statistical analysis lies outside these intervals.
        </p>
      </Tabs.Content>
    </Tabs.Root>
  </section>
{:else}<p role="status">
    Final result unavailable. Accepted state: {model.status?.state ??
      "Loading"}. A result becomes available after accepted success.
  </p>
  {#if model.resultError}<pre role="status">{errorText(
        model.resultError,
      )}</pre>{/if}
{/if}

<style>
  .final-results {
    display: grid;
    gap: var(--ui-space-3);
  }
  .filters {
    display: flex;
    flex-wrap: wrap;
    gap: var(--ui-space-3);
    margin-block: var(--ui-space-3);
  }
  .result-table {
    min-height: 18rem;
    overflow: auto;
  }
  .timing-table {
    min-height: 15rem;
    overflow: auto;
  }
  .selected-comparison {
    padding: var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
  }
  h3,
  h4,
  p {
    margin-block: var(--ui-space-2);
  }
</style>
