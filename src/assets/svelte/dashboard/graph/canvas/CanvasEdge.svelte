<script lang="ts">
  import type { Edge, Node } from "../../../contracts.generated/graph";
  import { ContextMenu } from "bits-ui";
  import { edgeEndpoints } from "./geometry";
  import { isActivationKey, type Point } from "./canvasState";
  import { edgePresentation } from "../presentation/registry";
  import type { CanvasEdgeAppearance } from "./appearance";

  interface Props {
    edge: Edge;
    source: Node;
    target: Node;
    sourcePosition: Point;
    targetPosition: Point;
    selected: boolean;
    appearance?: CanvasEdgeAppearance;
    onclick?: (event: MouseEvent) => void;
    oncontextmenu?: (event: MouseEvent) => void;
    onDelete?: () => void;
  }

  let {
    edge,
    source,
    target,
    sourcePosition,
    targetPosition,
    selected,
    appearance = undefined,
    onclick,
    oncontextmenu,
    onDelete = undefined,
  }: Props = $props();
  const markerId = $props.id();
  let edgeType = $derived(edge.type);
  let edgeStyle = $derived(edgePresentation(edge.type));
  let edgeLabel = $derived(edgeStyle?.label ? edgeStyle.label(edge) : edgeType);
  let geometry = $derived(edgeEndpoints(sourcePosition, targetPosition));
  let path = $derived(
    `M ${geometry.source.x} ${geometry.source.y} L ${geometry.target.x} ${geometry.target.y}`,
  );
  let labelPosition = $derived({
    x: (geometry.source.x + geometry.target.x) / 2,
    y: (geometry.source.y + geometry.target.y) / 2,
  });

  function handleKeydown(event: KeyboardEvent) {
    if (!onclick || !isActivationKey(event.key)) return;

    event.preventDefault();
    onclick(event as unknown as MouseEvent);
  }
</script>

{#snippet edgeTrigger({ props }: { props: Record<string, unknown> })}
  <g
    {...props}
    class={["canvas-edge", selected && "selected"]}
    style:--edge-color={edgeStyle?.color}
    style:--edge-dash={edgeStyle?.dashArray ?? "none"}
    style:--edge-opacity={appearance?.opacity}
    style:--edge-stroke={appearance?.stroke}
    style:--edge-stroke-width={appearance?.strokeWidth}
    data-graph-interactive={onclick || onDelete ? true : undefined}
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
      tabindex={onclick ? 0 : undefined}
      role="button"
      aria-disabled={onclick ? undefined : true}
      aria-pressed={onclick ? selected : undefined}
      aria-label={`${edgeLabel} relationship${selected ? ", selected" : ""}`}
      {onclick}
      onkeydown={handleKeydown}
    />
    <text
      class="canvas-edge-label"
      x={labelPosition.x}
      y={labelPosition.y}
      text-anchor="middle"
      dominant-baseline="central"
      aria-hidden="true">{edgeLabel}</text
    >
  </g>
{/snippet}

{#if onDelete}
  <ContextMenu.Root>
    <ContextMenu.Trigger child={edgeTrigger} {oncontextmenu} />
    <ContextMenu.Portal>
      <ContextMenu.Content
        class="dashboard-menu-content"
        sideOffset={6}
        aria-label="Edge actions"
      >
        <ContextMenu.Item class="dashboard-menu-item" onSelect={onDelete}
          >Delete</ContextMenu.Item
        >
      </ContextMenu.Content>
    </ContextMenu.Portal>
  </ContextMenu.Root>
{:else}
  {@render edgeTrigger({ props: {} })}
{/if}

<style>
  .canvas-edge-line {
    fill: none;
    stroke: var(--edge-stroke, var(--edge-color, var(--ui-color-text-muted)));
    stroke-opacity: var(--edge-opacity, 1);
    stroke-width: var(--edge-stroke-width, 2);
    stroke-dasharray: var(--edge-dash, none);
    pointer-events: none;
  }
  .canvas-edge-arrow {
    fill: var(--edge-stroke, var(--edge-color, var(--ui-color-text-muted)));
    fill-opacity: var(--edge-opacity, 1);
  }
  .canvas-edge.selected .canvas-edge-line {
    stroke: var(--ui-color-focus);
    stroke-width: 3;
  }
  .canvas-edge.selected .canvas-edge-arrow {
    fill: var(--ui-color-focus);
  }
  .canvas-edge-hit-target {
    fill: none;
    stroke: transparent;
    stroke-width: 16;
    cursor: default;
  }
  .canvas-edge[data-graph-interactive] .canvas-edge-hit-target {
    cursor: pointer;
  }
  .canvas-edge-hit-target:focus {
    outline: none;
  }
  .canvas-edge-hit-target:focus-visible {
    stroke: var(--ui-color-focus);
    stroke-opacity: 0.35;
  }
  .canvas-edge-label {
    fill: var(--ui-color-nav-secondary);
    font: 700 var(--ui-text-xs) var(--ui-font-mono);
    paint-order: stroke;
    pointer-events: none;
    stroke: var(--ui-color-canvas);
    stroke-linejoin: round;
    stroke-width: 5px;
  }
  .canvas-edge.selected .canvas-edge-label {
    font-weight: 800;
  }
</style>
