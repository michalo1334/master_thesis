<script lang="ts">
  import type { GraphContract } from "../../../contracts.generated/graph";
  import type { GraphValidationError } from "../../../contracts.generated/dashboard/graph";

  import Inspector from "../../../ui-kit/layout/Inspector.svelte";
  import InspectorField from "../../../ui-kit/layout/InspectorField.svelte";
  import ErrorMessages from "../ErrorMessages.svelte";
  import { pathsEqual } from "./validation-path";

  interface Props {
    graph: GraphContract;
    parentTitle?: string;
    onTitleChange: (title: string) => void;
    onOpenParent?: () => void;
    errors?: readonly GraphValidationError[];
  }

  let {
    graph,
    parentTitle = undefined,
    onTitleChange,
    onOpenParent = undefined,
    errors = [],
  }: Props = $props();
  const titleInputId = $props.id();
  const titleErrorsId = `${titleInputId}-errors`;
  let titleErrors = $derived(
    errors
      .filter((error) => pathsEqual(error.field_path, ["title"]))
      .map((error) => error.message),
  );
  let graphErrors = $derived(
    errors
      .filter((error) => !pathsEqual(error.field_path, ["title"]))
      .map((error) => error.message),
  );

  function updateTitle(event: Event): void {
    const input = event.currentTarget as HTMLInputElement;
    if (!input.value.trim()) {
      input.value = graph.title;
      return;
    }
    onTitleChange(input.value);
  }
</script>

<Inspector title="Graph">
  <ErrorMessages errors={graphErrors} class="graph-errors" />
  <div class="graph-title-field">
    <label for={titleInputId}>Title</label>
    <input
      id={titleInputId}
      aria-invalid={titleErrors.length ? "true" : undefined}
      aria-describedby={titleErrors.length ? titleErrorsId : undefined}
      type="text"
      value={graph.title}
      maxlength="255"
      onchange={updateTitle}
    />
    <ErrorMessages errors={titleErrors} id={titleErrorsId} />
  </div>
  <InspectorField
    fields={[
      { label: "Graph ID", value: graph.id },
      { label: "Revision", value: graph.revision_id ?? "Unsaved" },
      { label: "Revision kind", value: graph.revision_kind ?? "Draft" },
      { label: "Revision number", value: String(graph.revision_number ?? 0) },
      { label: "Nodes", value: String(graph.nodes.length) },
      { label: "Edges", value: String(graph.edges.length) },
    ]}
  />
  <div class="graph-parent-field">
    <span>Parent</span>
    {#if graph.parent_revision_id && onOpenParent}
      <button type="button" onclick={onOpenParent}>
        {parentTitle ?? graph.parent_revision_id}
      </button>
    {:else}
      <span class="graph-parent-value">
        {graph.parent_revision_id
          ? (parentTitle ?? graph.parent_revision_id)
          : "Root revision"}
      </span>
    {/if}
  </div>
</Inspector>

<style>
  .graph-title-field {
    display: grid;
    gap: var(--ui-space-1);
    margin-bottom: var(--ui-space-3);
  }
  .graph-title-field label {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }
  .graph-title-field input {
    min-width: 0;
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-surface);
    color: var(--ui-color-text);
    font: inherit;
  }
  .graph-title-field input:focus-visible {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: 1px;
  }
  :global(.graph-errors) {
    margin-bottom: var(--ui-space-3);
  }
  .graph-parent-field {
    display: grid;
    gap: var(--ui-space-1);
    margin-top: var(--ui-space-3);
  }
  .graph-parent-field > span:first-child {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }
  .graph-parent-field button,
  .graph-parent-value {
    width: fit-content;
    padding: 0;
    border: 0;
    background: transparent;
    color: var(--ui-color-text);
    font-family: var(--ui-font-mono);
    font-size: var(--ui-text-sm);
    text-align: start;
    word-break: break-all;
  }
  .graph-parent-field button {
    color: var(--ui-color-accent);
    text-decoration: underline;
  }
</style>
