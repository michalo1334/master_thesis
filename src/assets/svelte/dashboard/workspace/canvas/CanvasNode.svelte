<script lang="ts">
  import {
    graphNodeLabel,
    graphNodeMetadata,
    graphTypeLabel,
    type GraphNode,
    type GraphPoint,
  } from "../model";

  interface Props {
    node: GraphNode;
    position: GraphPoint;
    selected: boolean;
    source: boolean;
    dragging: boolean;
    onclick: (event: MouseEvent) => void;
    onpointerdown: (event: PointerEvent) => void;
  }

  let {
    node,
    position,
    selected,
    source,
    dragging,
    onclick,
    onpointerdown,
  }: Props = $props();
  let label = $derived(graphNodeLabel(node));
  let type = $derived(graphTypeLabel(node.type));
  let metadata = $derived(graphNodeMetadata(node));

  function handleKeydown(event: KeyboardEvent) {
    if (event.key !== "Enter" && event.key !== " ") return;

    event.preventDefault();
    onclick(event as unknown as MouseEvent);
  }
</script>

<g
  class={[
    "canvas-node",
    selected && "selected",
    source && "source",
    dragging && "dragging",
  ]}
  transform={`translate(${position.x} ${position.y})`}
  tabindex="0"
  role="button"
  aria-pressed={selected}
  aria-label={`${label}, ${type}${metadata ? `, ${metadata}` : ""}${selected ? ", selected" : ""}${source ? ", connection source" : ""}`}
  data-graph-interactive
  {onclick}
  {onpointerdown}
  onkeydown={handleKeydown}
>
  <title>{label} - {type}{metadata ? ` - ${metadata}` : ""}</title>
  <rect class="canvas-node-card" width="120" height="72" rx="7" />
  <circle class="canvas-node-glyph" cx="16" cy="18" r="6" />
  <text class="canvas-node-title" x="28" y="22">{label}</text>
  <text class="canvas-node-sub" x="10" y="43">{type}</text>
  <text class="canvas-node-sub" x="10" y="60">{metadata || "No metadata"}</text>
</g>

<style>
  .canvas-node {
    cursor: pointer;
  }
  .canvas-node.dragging {
    cursor: grabbing;
  }
  .canvas-node-card {
    fill: #fff;
    stroke: #8090a4;
    stroke-width: 1.2;
    filter: drop-shadow(0 2px 2px #17243c29);
  }
  .canvas-node.dragging .canvas-node-card {
    stroke: #0b6fe8;
    stroke-width: 3;
    filter: drop-shadow(0 4px 5px #17243c40);
  }
  .canvas-node.selected .canvas-node-card {
    stroke: #0b6fe8;
    stroke-width: 3;
  }
  .canvas-node.source .canvas-node-card {
    stroke: #c77a19;
    stroke-width: 3;
    stroke-dasharray: 5 3;
  }
  .canvas-node-glyph {
    fill: #e7f0fc;
    stroke: #32669f;
    stroke-width: 1.5;
    pointer-events: none;
  }
  .canvas-node-title {
    font-size: var(--ds-text-sm);
    font-weight: 700;
    fill: #1b2738;
    pointer-events: none;
  }
  .canvas-node-sub {
    font: var(--ds-text-xs) var(--ds-font-mono);
    fill: var(--ds-color-text-muted);
    pointer-events: none;
  }
  .canvas-node:focus {
    outline: none;
  }
  .canvas-node:focus-visible .canvas-node-card {
    stroke: var(--ds-color-focus);
    stroke-width: 3;
  }
  @media (forced-colors: active) {
    .canvas-node-card {
      filter: none;
    }
  }
</style>
