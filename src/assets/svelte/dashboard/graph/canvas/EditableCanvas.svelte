<script lang="ts">
  import Canvas from "./Canvas.svelte";
  import type { EditableGraphDocument } from "../EditableGraphDocument.svelte";

  interface Props {
    document: EditableGraphDocument;
  }

  let { document }: Props = $props();
</script>

<Canvas
  graph={document.graph}
  fitVersion={document.revision}
  selectedNodeId={document.canvasSelection.kind === "node"
    ? document.canvasSelection.nodeId
    : undefined}
  selectedEdgeId={document.canvasSelection.kind === "edge"
    ? document.canvasSelection.edgeId
    : undefined}
  onGraphChange={(graph) => (document.graph = graph)}
  onSelectNode={(nodeId) => document.selectNode(nodeId)}
  onSelectEdge={(edgeId) => document.selectEdge(edgeId)}
  onClearSelection={() => document.clearSelection()}
/>
