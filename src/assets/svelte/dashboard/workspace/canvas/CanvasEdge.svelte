<script lang="ts">
  import { edgeEndpoints } from "./fixtures";
  import type { CanvasEdgeData, CanvasNodeData } from "./fixtures";

  interface Props {
    edge: CanvasEdgeData;
    source: CanvasNodeData;
    target: CanvasNodeData;
    selected: boolean;
    onclick: (event: MouseEvent) => void;
  }

  let { edge, source, target, selected, onclick }: Props = $props();
  const markerId = $props.id();
  let geometry = $derived(edgeEndpoints(source, target));
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

<g
  class={["canvas-edge", edge.visualStyle, selected && "selected"]}
  data-graph-interactive
>
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
    aria-label={`${edge.visualStyle} ${edge.relationshipLabel} relationship from ${source.name} to ${target.name}${selected ? ", selected" : ""}`}
    {onclick}
    onkeydown={handleKeydown}
  />
  <text
    class="canvas-edge-label"
    x={labelPosition.x}
    y={labelPosition.y}
    text-anchor="middle"
    dominant-baseline="central"
    aria-hidden="true">{edge.relationshipLabel}</text
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
  .canvas-edge.trust .canvas-edge-line {
    stroke: #7c3aed;
    stroke-dasharray: 7 4;
  }
  .canvas-edge.trust .canvas-edge-arrow {
    fill: #7c3aed;
  }
  .canvas-edge.warning .canvas-edge-line {
    stroke: #d97706;
    stroke-dasharray: 7 4;
  }
  .canvas-edge.warning .canvas-edge-arrow {
    fill: #d97706;
  }
  .canvas-edge.standard.selected .canvas-edge-line {
    stroke: #0b6fe8;
    stroke-width: 3;
  }
  .canvas-edge.standard.selected .canvas-edge-arrow {
    fill: #0b6fe8;
  }
  .canvas-edge.trust.selected .canvas-edge-line {
    stroke: #5b21b6;
    stroke-width: 3;
  }
  .canvas-edge.trust.selected .canvas-edge-arrow {
    fill: #5b21b6;
  }
  .canvas-edge.warning.selected .canvas-edge-line {
    stroke: #9a3412;
    stroke-width: 3;
  }
  .canvas-edge.warning.selected .canvas-edge-arrow {
    fill: #9a3412;
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
  .canvas-edge.trust .canvas-edge-label {
    fill: #5b21b6;
  }
  .canvas-edge.warning .canvas-edge-label {
    fill: #9a3412;
  }
  .canvas-edge.selected .canvas-edge-label {
    font-weight: 800;
  }
</style>
