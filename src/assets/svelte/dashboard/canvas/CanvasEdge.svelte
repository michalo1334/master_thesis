<script lang="ts">
  import { edgeEndpoints } from "./geometry";
  import { type Edge, type Node, type NodeViewData } from "../contract";
  import type { Point } from "./canvasState";

  interface Props {
    edge: Edge;
    source: Node;
    target: Node;
    sourcePosition: Point;
    targetPosition: Point;
    selected: boolean;
    onclick: (event: MouseEvent) => void;
  }

  let {
    edge,
    source,
    target,
    sourcePosition,
    targetPosition,
    selected,
    onclick,
  }: Props = $props();
  const markerId = $props.id();
  let edgeType = $derived(edge.type);
  let geometry = $derived(edgeEndpoints(sourcePosition, targetPosition));
  let path = $derived(
    `M ${geometry.source.x} ${geometry.source.y} L ${geometry.target.x} ${geometry.target.y}`,
  );
  let labelPosition = $derived({
    x: (geometry.source.x + geometry.target.x) / 2,
    y: (geometry.source.y + geometry.target.y) / 2,
  });

  function handleKeydown(event: KeyboardEvent) {
    if (event.key !== "Enter" && event.key !== " ") return;

    event.preventDefault();
    onclick(event as unknown as MouseEvent);
  }
</script>

<g class={["canvas-edge", selected && "selected"]} data-graph-interactive>
  <defs>
    <marker
      id={markerId}
      markerWidth="8"
      markerHeight="8"
      refX="7"
      refY="3"
      orient="auto"
    >
      <path class="canvas-edge-arrow" d="M0 0 8 3 0 6Z" />
    </marker>
  </defs>
  <path class="canvas-edge-line" d={path} marker-end={`url(#${markerId})`} />
  <path
    class="canvas-edge-hit-target"
    d={path}
    tabindex="0"
    role="button"
    aria-pressed={selected}
    aria-label={`${edgeType} relationship from TODO to TODO}${selected ? ", selected" : ""}`}
    {onclick}
    onkeydown={handleKeydown}
  />
  <text
    class="canvas-edge-label"
    x={labelPosition.x}
    y={labelPosition.y}
    text-anchor="middle"
    dominant-baseline="central"
    aria-hidden="true">{edgeType}</text
  >
</g>

<style>
  .canvas-edge-line {
    fill: none;
    stroke: #59677a;
    stroke-width: 2;
    pointer-events: none;
  }
  .canvas-edge-arrow {
    fill: #59677a;
  }
  .canvas-edge.selected .canvas-edge-line {
    stroke: #0b6fe8;
    stroke-width: 3;
  }
  .canvas-edge.selected .canvas-edge-arrow {
    fill: #0b6fe8;
  }
  .canvas-edge-hit-target {
    fill: none;
    stroke: transparent;
    stroke-width: 16;
    cursor: pointer;
  }
  .canvas-edge-hit-target:focus {
    outline: none;
  }
  .canvas-edge-hit-target:focus-visible {
    stroke: var(--ds-color-focus);
    stroke-opacity: 0.35;
  }
  .canvas-edge-label {
    fill: #273447;
    font: 700 var(--ds-text-xs) var(--ds-font-mono);
    paint-order: stroke;
    pointer-events: none;
    stroke: var(--ds-color-canvas);
    stroke-linejoin: round;
    stroke-width: 5px;
  }
  .canvas-edge.selected .canvas-edge-label {
    font-weight: 800;
  }
</style>
