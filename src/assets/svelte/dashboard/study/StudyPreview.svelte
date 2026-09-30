<script lang="ts">
  import type {
    DescribeStudySpecificationReply,
    ManifestError,
  } from "../../contracts.generated/dashboard/evaluation";

  interface Props {
    content: Record<string, unknown> | null;
    reply: DescribeStudySpecificationReply | null;
    errors: readonly ManifestError[];
    isLoading: boolean;
    notice?: string;
  }

  let { content, reply, errors, isLoading, notice = "" }: Props = $props();

  function asText(value: unknown): string {
    if (value == null || value === "") return "—";
    if (typeof value === "object") return JSON.stringify(value);
    return String(value);
  }

  const scalarEntries = $derived(
    content
      ? Object.entries(content).filter(([, value]) => typeof value !== "object")
      : [],
  );
  const tiers = $derived(reply?.description?.tiers ?? []);
</script>

<section class="study-preview" aria-label="Study specification preview">
  {#if isLoading}
    <p class="study-preview-status" role="status">
      Describing study specification…
    </p>
  {/if}

  {#if errors.length > 0}
    <ul class="study-preview-errors" role="alert">
      {#each errors as error (error.path + error.message)}
        <li>{error.path}: {error.message}</li>
      {/each}
    </ul>
  {:else if notice}
    <p class="study-preview-errors" role="alert">{notice}</p>
  {:else if !reply && !isLoading}
    <p class="study-preview-empty">
      Open this tab to describe the current study specification.
    </p>
  {:else if reply && reply.status !== "ok"}
    <p class="study-preview-empty">
      The study specification could not be described.
    </p>
  {/if}

  {#if reply?.status === "ok" && reply.description}
    <section class="study-preview-section">
      <h3>Study identity</h3>
      <dl class="study-preview-keys">
        <div>
          <dt>study_id</dt>
          <dd>{reply.description.study_id}</dd>
        </div>
        <div>
          <dt>specification_version</dt>
          <dd>{reply.description.specification_version}</dd>
        </div>
      </dl>
    </section>

    <section class="study-preview-section">
      <h3>Declared tiers</h3>
      {#if tiers.length === 0}
        <p class="study-preview-empty">No tiers declared.</p>
      {:else}
        <ul class="study-preview-tiers">
          {#each tiers as tier (tier)}
            <li>{tier}</li>
          {/each}
        </ul>
      {/if}
    </section>

    {#if scalarEntries.length > 0}
      <section class="study-preview-section">
        <h3>Settings</h3>
        <dl class="study-preview-keys">
          {#each scalarEntries as [key, value] (key)}
            <div>
              <dt>{key}</dt>
              <dd>{asText(value)}</dd>
            </div>
          {/each}
        </dl>
      </section>
    {/if}
  {/if}
</section>

<style>
  .study-preview {
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-3);
    min-height: 0;
    overflow: auto;
  }

  .study-preview-status,
  .study-preview-errors,
  .study-preview-empty {
    margin: 0;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-radius: var(--ui-radius-sm);
    font-size: var(--ui-text-sm);
  }

  .study-preview-status {
    background: color-mix(in srgb, var(--ui-color-accent) 12%, transparent);
    color: inherit;
  }

  .study-preview-errors {
    background: var(--ui-color-danger-bg, var(--ui-color-warning-bg));
    color: var(--ui-color-danger-text, var(--ui-color-warning-text));
    list-style: none;
  }

  .study-preview-empty {
    background: var(--ui-color-surface);
    color: var(--ui-color-text-secondary);
  }

  .study-preview-section {
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-2);
  }

  .study-preview-section h3 {
    margin: 0;
    font-size: var(--ui-text-base);
  }

  .study-preview-keys {
    display: grid;
    grid-template-columns: minmax(10rem, 1fr) minmax(0, 2fr);
    gap: var(--ui-space-1) var(--ui-space-3);
    margin: 0;
    font-size: var(--ui-text-sm);
  }

  .study-preview-keys div {
    display: contents;
  }

  .study-preview-keys dt {
    color: var(--ui-color-text-secondary);
  }

  .study-preview-keys dd {
    margin: 0;
    overflow-wrap: anywhere;
  }

  .study-preview-tiers {
    margin: 0;
    padding-left: 1.25rem;
    font-size: var(--ui-text-sm);
  }
</style>
