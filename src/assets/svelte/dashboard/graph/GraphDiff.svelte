<script lang="ts">
  import Canvas from "./canvas/Canvas.svelte";
  import type {
    GraphDiffDocument,
    GraphDiffStatus,
  } from "./GraphDiffDocument.svelte";

  interface Props {
    document: GraphDiffDocument;
  }

  let { document }: Props = $props();

  function nodeAppearance(status: GraphDiffStatus) {
    if (status === "added") {
      return {
        cardFill:
          "color-mix(in srgb, var(--ds-color-positive) 14%, var(--ds-color-paper))",
        cardStroke: "var(--ds-color-positive)",
        cardStrokeWidth: 2.5,
      };
    }
    if (status === "removed") {
      return {
        cardFill:
          "color-mix(in srgb, var(--ds-color-danger) 12%, var(--ds-color-paper))",
        cardStroke: "var(--ds-color-danger)",
        cardStrokeWidth: 2.5,
      };
    }
    return { cardOpacity: 0.45 };
  }

  function edgeAppearance(status: GraphDiffStatus) {
    if (status === "added") {
      return { stroke: "var(--ds-color-positive)", strokeWidth: 3 };
    }
    if (status === "removed") {
      return { stroke: "var(--ds-color-danger)", strokeWidth: 3 };
    }
    return { opacity: 0.35 };
  }
</script>

<section class="graph-diff" aria-label={document.title}>
  <Canvas
    graph={document.graph}
    fitVersion={1}
    nodeAppearance={(node) =>
      nodeAppearance(document.nodeStatusById.get(node.id) ?? "unchanged")}
    edgeAppearance={(edge) =>
      edgeAppearance(document.edgeStatusById.get(edge.id) ?? "unchanged")}
    ariaLabel="Read-only graph comparison canvas"
  />
  <aside class="graph-diff-legend" aria-label="Graph comparison legend">
    <strong>Graph comparison</strong>
    <ul>
      <li><span class="added" aria-hidden="true"></span>Added</li>
      <li><span class="removed" aria-hidden="true"></span>Removed</li>
      <li><span class="unchanged" aria-hidden="true"></span>Unchanged</li>
    </ul>
    <p>
      Nodes: {document.nodeCounts.added} added, {document.nodeCounts.removed} removed,
      {document.nodeCounts.unchanged} unchanged. Edges: {document.edgeCounts
        .added} added,
      {document.edgeCounts.removed} removed, {document.edgeCounts.unchanged} unchanged.
    </p>
  </aside>
</section>

<style>
  .graph-diff {
    position: relative;
    height: 100%;
    min-height: 0;
  }

  .graph-diff-legend {
    position: absolute;
    top: var(--ds-space-3);
    left: var(--ds-space-3);
    max-width: min(28rem, calc(100% - 2 * var(--ds-space-3)));
    padding: var(--ds-space-2) var(--ds-space-3);
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-sm);
    color: var(--ds-color-text);
    font-size: var(--ds-text-sm);
  }

  strong,
  p {
    margin: 0;
  }

  ul {
    display: flex;
    flex-wrap: wrap;
    gap: var(--ds-space-2);
    margin: var(--ds-space-1) 0;
    padding: 0;
    list-style: none;
  }

  li {
    display: flex;
    align-items: center;
    gap: var(--ds-space-1);
  }

  li span {
    width: 0.625rem;
    height: 0.625rem;
    border-radius: 50%;
  }

  .added {
    background: var(--ds-color-positive);
  }

  .removed {
    background: var(--ds-color-danger);
  }

  .unchanged {
    background: var(--ds-color-text-faint);
    opacity: 0.5;
  }
</style>
