<script lang="ts">
  import type { LoadedGraph } from "../../contract";
  import Inspector from "../Inspector.svelte";
  import InspectorField from "../InspectorField.svelte";

  interface Props {
    graph: LoadedGraph;
    parentTitle?: string;
    onTitleChange: (title: string) => void;
    onOpenParent?: () => void;
  }

  let {
    graph,
    parentTitle = undefined,
    onTitleChange,
    onOpenParent = undefined,
  }: Props = $props();

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
  <label class="graph-title-field">
    <span>Title</span>
    <input
      type="text"
      value={graph.title}
      maxlength="255"
      onchange={updateTitle}
    />
  </label>
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
    gap: var(--ds-space-1);
    margin-bottom: var(--ds-space-3);
  }
  .graph-title-field span {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-xs);
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }
  .graph-title-field input {
    min-width: 0;
    min-height: var(--ds-control-height);
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-surface);
    color: var(--ds-color-text);
    font: inherit;
  }
  .graph-title-field input:focus-visible {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 1px;
  }
  .graph-parent-field {
    display: grid;
    gap: var(--ds-space-1);
    margin-top: var(--ds-space-3);
  }
  .graph-parent-field > span:first-child {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-xs);
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
    color: var(--ds-color-text);
    font-family: var(--ds-font-mono);
    font-size: var(--ds-text-sm);
    text-align: start;
    word-break: break-all;
  }
  .graph-parent-field button {
    color: var(--ds-color-accent);
    text-decoration: underline;
  }
</style>
