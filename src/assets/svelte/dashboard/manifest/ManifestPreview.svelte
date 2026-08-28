<script lang="ts">
  import type {
    DescribeManifestPlanGroup,
    DescribeManifestReply,
    ManifestError,
  } from "../../contracts.generated/dashboard/evaluation";

  interface Props {
    content: Record<string, unknown> | null;
    reply: DescribeManifestReply | null;
    errors: readonly ManifestError[];
    isLoading: boolean;
    notice?: string;
  }

  let { content, reply, errors, isLoading, notice = "" }: Props = $props();

  function asRecord(value: unknown): Record<string, unknown> | null {
    return typeof value === "object" && value !== null && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  }

  function asArray(value: unknown): unknown[] {
    return Array.isArray(value) ? value : [];
  }

  function asText(value: unknown): string {
    if (value == null || value === "") return "—";
    if (typeof value === "object") return JSON.stringify(value);
    return String(value);
  }

  function asNumber(value: unknown): string {
    return typeof value === "number" && Number.isFinite(value)
      ? String(value)
      : "—";
  }

  function entryHost(value: unknown): string {
    const attacker = asRecord(value);
    const entry = attacker ? asRecord(attacker.entry_host) : null;
    return entry ? asText(entry.value ?? entry.host ?? entry.id) : "—";
  }

  function scalarEntries(value: unknown): [string, string][] {
    const record = asRecord(value);
    return record
      ? Object.entries(record).map(([key, entry]) => [
          key,
          typeof entry === "object" && entry !== null
            ? JSON.stringify(entry)
            : asText(entry),
        ])
      : [];
  }

  function groupLabel(group: DescribeManifestPlanGroup | null | undefined) {
    if (!group) return null;
    return {
      strategy: asText(group.strategy),
      variant: asText(group.model_variant),
      budget: asNumber(group.budget),
      seeds: asArray(group.selection_seeds)
        .map((seed) => asNumber(seed))
        .join(", "),
    };
  }

  function groupSummary(
    group: DescribeManifestPlanGroup | null | undefined,
  ): string {
    const label = groupLabel(group);
    return label
      ? `${label.strategy} (${label.variant}), budget ${label.budget}, seeds ${label.seeds}`
      : "—";
  }

  const sourceEntries = $derived(scalarEntries(content?.source));
  // ponytail: rendered as structured cards from reply.comparison_groups instead
  const analysisEntries = $derived(
    scalarEntries(content?.analysis).filter(
      ([key]) => key !== "primary_comparisons",
    ),
  );
  const evaluationEntries = $derived(scalarEntries(content?.evaluation));
  const modelVariants = $derived(asArray(content?.model_variants));
  const plans = $derived(reply?.plans ?? []);
  const groups = $derived(reply?.comparison_groups ?? []);
</script>

<section class="manifest-preview" aria-label="Manifest preview">
  {#if isLoading}
    <p class="manifest-preview-status" role="status">Describing manifest…</p>
  {/if}

  {#if errors.length > 0}
    <ul class="manifest-preview-errors" role="alert">
      {#each errors as error (error.path + error.message)}
        <li>{error.path}: {error.message}</li>
      {/each}
    </ul>
  {:else if notice}
    <p class="manifest-preview-errors" role="alert">{notice}</p>
  {:else if !reply && !isLoading}
    <p class="manifest-preview-empty">
      Open this tab to describe the current manifest.
    </p>
  {:else if reply && reply.status !== "ok"}
    <p class="manifest-preview-empty">The manifest could not be described.</p>
  {/if}

  {#if reply?.status === "ok"}
    <section
      class="manifest-preview-section"
      aria-labelledby="manifest-preview-source-title"
    >
      <h3 id="manifest-preview-source-title">Source and attacker</h3>
      <dl class="manifest-preview-keys">
        {#each sourceEntries as [key, value] (key)}
          <div>
            <dt>{key}</dt>
            <dd>{value}</dd>
          </div>
        {/each}
        <div>
          <dt>attacker.entry_host</dt>
          <dd>{entryHost(content?.attacker)}</dd>
        </div>
        <div>
          <dt>attacker.max_attempts</dt>
          <dd>{asNumber(asRecord(content?.attacker)?.max_attempts)}</dd>
        </div>
      </dl>
    </section>

    <section
      class="manifest-preview-section"
      aria-labelledby="manifest-preview-variants-title"
    >
      <h3 id="manifest-preview-variants-title">Model variants</h3>
      {#if modelVariants.length === 0}
        <p class="manifest-preview-empty">No model variants declared.</p>
      {:else}
        <div class="manifest-preview-table-wrap">
          <table class="manifest-preview-table">
            <thead>
              <tr>
                <th scope="col">ID</th>
                <th scope="col">Objective</th>
                <th scope="col">Pre-attack feasibility required</th>
              </tr>
            </thead>
            <tbody>
              {#each modelVariants as variant, index (index)}
                {@const record = asRecord(variant)}
                <tr>
                  <th scope="row">{record ? asText(record.id) : "—"}</th>
                  <td>{record ? asText(record.objective) : "—"}</td>
                  <td>
                    {record
                      ? asText(record.require_pre_attack_feasibility)
                      : "—"}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </section>

    <section
      class="manifest-preview-section"
      aria-labelledby="manifest-preview-plans-title"
    >
      <h3 id="manifest-preview-plans-title">Planned strategy runs</h3>
      {#if plans.length === 0}
        <p class="manifest-preview-empty">No strategy runs planned.</p>
      {:else}
        <div class="manifest-preview-table-wrap">
          <table class="manifest-preview-table">
            <thead>
              <tr>
                <th scope="col">Strategy</th>
                <th scope="col">Model variant</th>
                <th scope="col">Budget</th>
                <th scope="col">Selection seed</th>
              </tr>
            </thead>
            <tbody>
              {#each plans as plan, index (index)}
                <tr>
                  <th scope="row">{asText(plan.strategy)}</th>
                  <td>{asText(plan.model_variant)}</td>
                  <td>{asNumber(plan.budget)}</td>
                  <td>{asNumber(plan.selection_seed)}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </section>

    <section
      class="manifest-preview-section"
      aria-labelledby="manifest-preview-groups-title"
    >
      <h3 id="manifest-preview-groups-title">Primary comparisons</h3>
      {#if groups.length === 0}
        <p class="manifest-preview-empty">No primary comparisons declared.</p>
      {:else}
        <ul class="manifest-preview-cards">
          {#each groups as group (group.index)}
            <li class="manifest-preview-card">
              <dl class="manifest-preview-keys">
                <div>
                  <dt>Outcome</dt>
                  <dd>{asText(group.outcome)}</dd>
                </div>
                <div>
                  <dt>Tested</dt>
                  <dd>{groupSummary(group.tested)}</dd>
                </div>
                <div>
                  <dt>Baseline</dt>
                  <dd>{groupSummary(group.baseline)}</dd>
                </div>
              </dl>
            </li>
          {/each}
        </ul>
      {/if}
    </section>

    <section
      class="manifest-preview-section"
      aria-labelledby="manifest-preview-analysis-title"
    >
      <h3 id="manifest-preview-analysis-title">Analysis settings</h3>
      {#if analysisEntries.length === 0}
        <p class="manifest-preview-empty">No analysis settings declared.</p>
      {:else}
        <dl class="manifest-preview-keys">
          {#each analysisEntries as [key, value] (key)}
            <div>
              <dt>{key}</dt>
              <dd>{value}</dd>
            </div>
          {/each}
        </dl>
      {/if}
    </section>

    <section
      class="manifest-preview-section"
      aria-labelledby="manifest-preview-evaluation-title"
    >
      <h3 id="manifest-preview-evaluation-title">Evaluation settings</h3>
      {#if evaluationEntries.length === 0}
        <p class="manifest-preview-empty">No evaluation settings declared.</p>
      {:else}
        <dl class="manifest-preview-keys">
          {#each evaluationEntries as [key, value] (key)}
            <div>
              <dt>{key}</dt>
              <dd>{value}</dd>
            </div>
          {/each}
        </dl>
      {/if}
    </section>
  {/if}
</section>

<style>
  .manifest-preview {
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-3);
    min-height: 0;
    overflow: auto;
  }

  .manifest-preview-status,
  .manifest-preview-errors,
  .manifest-preview-empty {
    margin: 0;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-radius: var(--ui-radius-sm);
    font-size: var(--ui-text-sm);
  }

  .manifest-preview-status {
    background: color-mix(in srgb, var(--ui-color-accent) 12%, transparent);
    color: inherit;
  }

  .manifest-preview-errors {
    background: var(--ui-color-danger-bg, var(--ui-color-warning-bg));
    color: var(--ui-color-danger-text, var(--ui-color-warning-text));
    list-style: none;
  }

  .manifest-preview-empty {
    color: var(--ui-color-text-secondary);
  }

  .manifest-preview-section h3 {
    margin: 0 0 var(--ui-space-2);
    font-size: var(--ui-text-base);
  }

  .manifest-preview-keys {
    display: grid;
    margin: 0;
    gap: var(--ui-space-2);
  }

  @media (min-width: 40.0625em) {
    .manifest-preview-keys {
      grid-template-columns: repeat(auto-fill, minmax(14rem, 1fr));
    }
  }

  .manifest-preview-keys div {
    min-width: 0;
    padding: var(--ui-space-2) var(--ui-space-3);
    border: 1px solid var(--ui-color-border-soft);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-surface);
  }

  .manifest-preview-keys dt {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    text-transform: uppercase;
    overflow-wrap: anywhere;
  }

  .manifest-preview-keys dd {
    margin: var(--ui-space-1) 0 0;
    overflow-wrap: anywhere;
  }

  .manifest-preview-cards {
    display: grid;
    margin: 0;
    padding: 0;
    gap: var(--ui-space-2);
    list-style: none;
  }

  @media (min-width: 40.0625em) {
    .manifest-preview-cards {
      grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr));
    }
  }

  .manifest-preview-card {
    min-width: 0;
    padding: var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }

  .manifest-preview-card .manifest-preview-keys div {
    padding: 0;
    border: 0;
    background: transparent;
  }

  .manifest-preview-table-wrap {
    max-height: 20rem;
    overflow: auto;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }

  .manifest-preview-table {
    width: 100%;
    border-collapse: collapse;
    text-align: left;
    font-size: var(--ui-text-sm);
  }

  .manifest-preview-table th,
  .manifest-preview-table td {
    padding: var(--ui-space-2) var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border);
    white-space: nowrap;
  }

  .manifest-preview-table thead th {
    position: sticky;
    top: 0;
    background: var(--ui-color-paper);
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    text-transform: uppercase;
  }

  .manifest-preview-table tbody tr:last-child > * {
    border-bottom: 0;
  }
</style>
