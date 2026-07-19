<script lang="ts">
  import type { Selectable } from "./contract";
import type { WorkspaceDocument } from "./workspace/WorkspaceDocument.svelte";
import { inspectorFor } from "./canvas/inspectorMappings";

  interface Props {
    document: WorkspaceDocument | undefined;
  }

  let { document }: Props = $props();

  let selectable = $derived.by((): Selectable | undefined => {
    if (!document || document.kind !== "canvas") return undefined;
    const sel = document.selection;
    if (sel.kind === "node")
      return document.graph.nodes.find((n: { id: string }) => n.id === sel.nodeId);
    if (sel.kind === "edge")
      return document.graph.edges.find((e: { id: string }) => e.id === sel.edgeId);
    return undefined;
  });

  let InspectorComponent = $derived(
    selectable ? inspectorFor(selectable) : null,
  );
</script>

{#if InspectorComponent}
  <InspectorComponent {selectable} />
{/if}
