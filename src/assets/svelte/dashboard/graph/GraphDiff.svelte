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
          "color-mix(in srgb, var(--ui-color-positive) 14%, var(--ui-color-paper))",
        cardStroke: "var(--ui-color-positive)",
        cardStrokeWidth: 2.5,
      };
    }
    if (status === "removed") {
      return {
        cardFill:
          "color-mix(in srgb, var(--ui-color-danger) 12%, var(--ui-color-paper))",
        cardStroke: "var(--ui-color-danger)",
        cardStrokeWidth: 2.5,
      };
    }
    return { cardOpacity: 0.45 };
  }

  function edgeAppearance(status: GraphDiffStatus) {
    if (status === "added") {
      return { stroke: "var(--ui-color-positive)", strokeWidth: 3 };
    }
    if (status === "removed") {
      return { stroke: "var(--ui-color-danger)", strokeWidth: 3 };
    }
    return { opacity: 0.35 };
  }
</script>

<section class="graph-diff" aria-label={document.title}>
  {#if document.status === "loading"}
    <p class="graph-diff-status">Loading graph comparison…</p>
  {:else if document.status === "error"}
    <p class="graph-diff-status">Could not load graph comparison.</p>
  {:else}
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
  {/if}
</section>

<style>
  .graph-diff {
    position: relative;
    height: 100%;
    min-height: 0;
  }

  .graph-diff-legend {
    position: absolute;
    top: var(--ui-space-3);
    left: var(--ui-space-3);
    max-width: min(28rem, calc(100% - 2 * var(--ui-space-3)));
    padding: var(--ui-space-2) var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-sm);
    color: var(--ui-color-text);
    font-size: var(--ui-text-sm);
  }
  .graph-diff-status {
    padding: var(--ui-space-3);
  }

  strong,
  p {
    margin: 0;
  }

  ul {
    display: flex;
    flex-wrap: wrap;
    gap: var(--ui-space-2);
    margin: var(--ui-space-1) 0;
    padding: 0;
    list-style: none;
  }

  li {
    display: flex;
    align-items: center;
    gap: var(--ui-space-1);
  }

  li span {
    width: 0.625rem;
    height: 0.625rem;
    border-radius: 50%;
  }

  .added {
    background: var(--ui-color-positive);
  }

  .removed {
    background: var(--ui-color-danger);
  }

  .unchanged {
    background: var(--ui-color-text-faint);
    opacity: 0.5;
  }
</style>
