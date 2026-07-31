<script lang="ts">
  import { ContextMenu } from "bits-ui";
  import type { Node } from "../../contract";
  import type { Point } from "./canvasState";
  import { nodePresentation } from "../presentation/registry";
  import type { CanvasNodeAppearance } from "./appearance";

  interface Props {
    node: Node;
    position: Point;
    selected: boolean;
    source: boolean;
    connectionDirection?: "forward" | "reverse" | "both";
    dragging: boolean;
    appearance?: CanvasNodeAppearance;
    onclick?: (event: MouseEvent) => void;
    oncontextmenu?: (event: MouseEvent) => void;
    onpointerdown?: (event: PointerEvent) => void;
    onconnectorpointerdown?: (event: PointerEvent) => void;
    onDelete?: () => void;
  }

  let {
    node,
    position,
    selected,
    source,
    connectionDirection = undefined,
    dragging,
    appearance = undefined,
    onclick,
    oncontextmenu,
    onpointerdown,
    onconnectorpointerdown,
    onDelete = undefined,
  }: Props = $props();

  let pres = $derived(nodePresentation(node.type));
  let InfoComponent = $derived(pres?.info ?? null);
  let nodeStyle = $derived(
    pres ? { color: pres.color, component: pres.glyph } : null,
  );

  function handleKeydown(event: KeyboardEvent) {
    if (!onclick || (event.key !== "Enter" && event.key !== " ")) return;

    event.preventDefault();
    onclick(event as unknown as MouseEvent);
  }
</script>

{#snippet nodeTrigger({ props }: { props: Record<string, unknown> })}
  <g
    {...props}
    class={[
      "canvas-node",
      selected && "selected",
      source && "source",
      dragging && "dragging",
      connectionDirection && `connection-${connectionDirection}`,
    ]}
    transform={`translate(${position.x} ${position.y})`}
    style:--node-color={nodeStyle?.color}
    style:--node-card-fill={appearance?.cardFill}
    style:--node-card-opacity={appearance?.cardOpacity}
    style:--node-card-stroke={appearance?.cardStroke}
    style:--node-card-stroke-width={appearance?.cardStrokeWidth}
    tabindex={onclick ? 0 : undefined}
    role="button"
    aria-disabled={onclick ? undefined : true}
    aria-pressed={onclick ? selected : undefined}
    aria-label={`${node.type}${selected ? ", selected" : ""}${source ? ", connection source" : ""}${connectionDirection ? `, valid ${connectionDirection} connection target` : ""}`}
    data-graph-interactive={onclick || onpointerdown || onDelete
      ? true
      : undefined}
    {onclick}
    {onpointerdown}
    onkeydown={handleKeydown}
  >
    <title>{node.type}</title>
    <rect class="canvas-node-card" width="120" height="72" rx="7" />
    {#if nodeStyle}
      <nodeStyle.component />
    {:else}
      <circle class="canvas-node-glyph" cx="16" cy="18" r="6" />
    {/if}
    {#if InfoComponent}
      <InfoComponent {node} />
    {:else}
      <text class="canvas-node-title" x="10" y="22">{node.type}</text>
    {/if}
    <text class="canvas-node-sub" x="10" y="43">{node.type}</text>
    {#if onconnectorpointerdown}
      <circle
        class="canvas-node-connector"
        cx="120"
        cy="36"
        r="6"
        role="button"
        tabindex="0"
        aria-label={`Create connection from ${node.type}`}
        data-graph-interactive
        onpointerdown={onconnectorpointerdown}
      />
    {/if}
  </g>
{/snippet}

{#if onDelete}
  <ContextMenu.Root>
    <ContextMenu.Trigger child={nodeTrigger} {oncontextmenu} />
    <ContextMenu.Portal>
      <ContextMenu.Content
        class="dashboard-menu-content"
        sideOffset={6}
        aria-label="Node actions"
      >
        <ContextMenu.Item class="dashboard-menu-item" onSelect={onDelete}
          >Delete</ContextMenu.Item
        >
      </ContextMenu.Content>
    </ContextMenu.Portal>
  </ContextMenu.Root>
{:else}
  {@render nodeTrigger({ props: {} })}
{/if}

<style>
  .canvas-node {
    cursor: default;
  }
  .canvas-node[data-graph-interactive] {
    cursor: pointer;
  }
  .canvas-node.dragging {
    cursor: grabbing;
  }
  .canvas-node-card {
    fill: var(--node-card-fill, var(--ds-color-paper));
    fill-opacity: var(--node-card-opacity, 1);
    stroke: var(
      --node-card-stroke,
      var(--node-color, var(--ds-color-text-faint))
    );
    stroke-width: var(--node-card-stroke-width, 1.2);
    filter: drop-shadow(
      0 2px 2px color-mix(in srgb, var(--ds-color-nav) 16%, transparent)
    );
  }
  .canvas-node.dragging .canvas-node-card {
    stroke: var(--ds-color-focus);
    stroke-width: 3;
    filter: drop-shadow(
      0 4px 5px color-mix(in srgb, var(--ds-color-nav) 25%, transparent)
    );
  }
  .canvas-node.selected .canvas-node-card {
    stroke: var(--ds-color-focus);
    stroke-width: 3;
  }
  .canvas-node.source .canvas-node-card {
    stroke: var(--ds-color-preview-edge);
    stroke-width: 3;
    stroke-dasharray: 5 3;
  }
  .canvas-node.connection-forward .canvas-node-card {
    stroke: var(--ds-color-preview-edge);
    stroke-width: 3;
  }
  .canvas-node.connection-reverse .canvas-node-card {
    stroke: var(--ds-color-focus);
    stroke-width: 3;
    stroke-dasharray: 5 3;
  }
  .canvas-node.connection-both .canvas-node-card {
    stroke: var(--ds-color-focus);
    stroke-width: 3;
    stroke-dasharray: 2 2 7 2;
  }
  .canvas-node-glyph {
    fill: var(--ds-color-accent-soft);
    stroke: var(--node-color, var(--ds-color-accent));
    stroke-width: 1.5;
    pointer-events: none;
  }
  .canvas-node-title {
    font-size: var(--ds-text-sm);
    font-weight: 700;
    fill: var(--ds-color-text);
    pointer-events: none;
  }
  .canvas-node-sub {
    font: var(--ds-text-xs) var(--ds-font-mono);
    fill: var(--ds-color-text-muted);
    pointer-events: none;
  }
  .canvas-node-connector {
    fill: var(--ds-color-paper);
    stroke: var(--node-color, var(--ds-color-accent));
    stroke-width: 2;
    cursor: crosshair;
  }
  .canvas-node-connector:hover {
    fill: var(--ds-color-accent-soft);
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
