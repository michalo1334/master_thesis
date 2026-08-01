<script lang="ts">
  import type { GraphSummary, LoadedGraph, Selectable } from "../contract";
  import type { WorkspaceDocument } from "../workspace/WorkspaceDocument.svelte";
  import GraphInspector from "./graph/GraphInspector.svelte";
  import EditableSelectionInspector from "./graph/EditableSelectionInspector.svelte";

  interface Props {
    document: WorkspaceDocument | undefined;
    summaries?: readonly GraphSummary[];
  }

  type InspectorSelection =
    | { kind: "selectable"; selectable: Selectable }
    | { kind: "graph"; graph: LoadedGraph; parentTitle?: string }
    | undefined;

  let { document, summaries = [] }: Props = $props();

  let selection = $derived.by((): InspectorSelection => {
    if (!document || document.kind !== "graph") return undefined;
    const selectable = document.selection;
    if (selectable) return { kind: "selectable", selectable };

    const parentTitle = document.graph.parent_id
      ? summaries.find(({ id }) => id === document.graph.parent_id)?.title
      : undefined;
    return { kind: "graph", graph: document.graph, parentTitle };
  });
</script>

{#if selection?.kind === "graph"}
  <GraphInspector graph={selection.graph} parentTitle={selection.parentTitle} />
{:else if selection?.kind === "selectable" && document?.kind === "graph"}
  <EditableSelectionInspector
    selectable={selection.selectable}
    onUpdate={(selectable) => document.updateSelection(selectable)}
  />
{/if}
