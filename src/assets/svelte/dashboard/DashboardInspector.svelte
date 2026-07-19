<script lang="ts">
  import type { WorkspaceDocument } from "./document/WorkspaceDocument.svelte";
  import CanvasNodeInspector from "./canvas/inspectors/CanvasNodeInspector.svelte";
  import CanvasEdgeInspector from "./canvas/inspectors/CanvasEdgeInspector.svelte";

  interface Props {
    document: WorkspaceDocument | undefined;
  }

  let { document }: Props = $props();

  let selectedNode = $derived.by(() => {
    if (!document || document.kind !== "canvas") return undefined;
    const sel = document.selection;
    if (sel.kind !== "node") return undefined;
    return document.graph.nodes.find((n) => n.id === sel.nodeId);
  });

  let selectedEdge = $derived.by(() => {
    if (!document || document.kind !== "canvas") return undefined;
    const sel = document.selection;
    if (sel.kind !== "edge") return undefined;
    return document.graph.edges.find((e) => e.id === sel.edgeId);
  });
</script>

{#if selectedNode}
  <CanvasNodeInspector node={selectedNode} />
{:else if selectedEdge}
  <CanvasEdgeInspector edge={selectedEdge} />
{/if}
