<script lang="ts">
  import type { LoadedGraph } from "../../contract";
  import type { AnalysisOption } from "../../dashboard-api";
  import type { FilterableTableColumn } from "../../controls/FilterableTable.types";
  import Inspector from "../Inspector.svelte";
  import InspectorField from "../InspectorField.svelte";
  import OptionPickerDialog from "../../ui/OptionPickerDialog.svelte";

  interface Props {
    graph: LoadedGraph;
    parentTitle?: string;
    onTitleChange: (title: string) => void;
    onOpenParent?: () => void;
    analyses?: readonly AnalysisOption[];
    analysisIds?: readonly string[];
    analysesStatus?: string;
    onLoadAnalyses?: () => Promise<boolean>;
    onAnalysesChange?: (analysisIds: string[]) => Promise<boolean>;
  }

  let {
    graph,
    parentTitle = undefined,
    onTitleChange,
    onOpenParent = undefined,
    analyses = [],
    analysisIds = [],
    analysesStatus = "",
    onLoadAnalyses = async () => true,
    onAnalysesChange = undefined,
  }: Props = $props();

  const analysisColumns: readonly FilterableTableColumn<AnalysisOption>[] = [
    {
      key: "title",
      header: "Title",
      getValue: (analysis) => analysis.title,
      filterable: true,
    },
  ];
  let analysisPickerOpen = $state(false);
  let selectedAnalyses = $derived(
    analysisIds.map(
      (id) =>
        analyses.find((analysis) => analysis.id === id) ?? { id, title: id },
    ),
  );

  function updateTitle(event: Event): void {
    const input = event.currentTarget as HTMLInputElement;
    if (!input.value.trim()) {
      input.value = graph.title;
      return;
    }
    onTitleChange(input.value);
  }

  async function openAnalysisPicker(): Promise<void> {
    await onLoadAnalyses();
    analysisPickerOpen = true;
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
  <div class="graph-analyses-field">
    <span>Analyses</span>
    {#if selectedAnalyses.length}
      <ul>
        {#each selectedAnalyses as analysis (analysis.id)}
          <li>{analysis.title}</li>
        {/each}
      </ul>
    {:else}
      <span class="graph-analyses-empty">No analyses</span>
    {/if}
    <button
      type="button"
      disabled={!onAnalysesChange}
      onclick={openAnalysisPicker}>Change analyses</button
    >
  </div>
</Inspector>

<OptionPickerDialog
  open={analysisPickerOpen}
  onOpenChange={(open) => (analysisPickerOpen = open)}
  items={analyses}
  title="Change analyses"
  description="Select analyses for this graph revision."
  getKey={(analysis) => analysis.id}
  columns={analysisColumns}
  mode="multiple"
  initialSelection={analysisIds}
  minSelections={0}
  emptyMessage="No analyses available."
  status={analysesStatus}
  onConfirm={(selected) =>
    onAnalysesChange?.(selected.map(({ id }) => id)) ?? false}
/>

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
  .graph-analyses-field {
    display: grid;
    gap: var(--ds-space-1);
    margin-top: var(--ds-space-3);
  }
  .graph-analyses-field > span:first-child {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-xs);
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }
  .graph-analyses-field ul {
    display: grid;
    gap: 0.125rem;
    margin: 0;
    padding: 0;
    list-style: none;
    font-size: var(--ds-text-sm);
  }
  .graph-analyses-empty {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
  }
  .graph-analyses-field button {
    width: fit-content;
    min-height: var(--ds-control-height);
    margin-top: var(--ds-space-1);
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-surface);
  }
</style>
