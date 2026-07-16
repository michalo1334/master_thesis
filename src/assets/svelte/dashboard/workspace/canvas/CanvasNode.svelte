<script lang="ts">
  import type { CanvasNodeData } from "./fixtures";

  interface Props {
    node: CanvasNodeData;
    selected: boolean;
    source: boolean;
    dragging: boolean;
    onclick: (event: MouseEvent) => void;
    onpointerdown: (event: PointerEvent) => void;
  }

  let { node, selected, source, dragging, onclick, onpointerdown }: Props =
    $props();

  function handleKeydown(event: KeyboardEvent) {
    if (event.key !== "Enter" && event.key !== " ") return;

    event.preventDefault();
    onclick(event as unknown as MouseEvent);
  }
</script>

<g
  class={[
    "canvas-node",
    node.critical && "critical",
    selected && "selected",
    source && "source",
    dragging && "dragging",
  ]}
  transform={`translate(${node.x} ${node.y})`}
  tabindex="0"
  role="button"
  aria-pressed={selected}
  aria-label={`${node.name}, ${node.assetKind}${selected ? ", selected" : ""}${source ? ", connection source" : ""}`}
  data-graph-interactive
  {onclick}
  {onpointerdown}
  onkeydown={handleKeydown}
>
  <title>{node.name}</title>
  <rect class="canvas-node-card" width="120" height="72" rx="7" />
  <circle class="canvas-node-icon-bg" cx="25" cy="28" r="15" />
  {#if node.assetKind === "Database"}
    <path
      class="canvas-node-glyph"
      d="M17 22c0-4 16-4 16 0v13c0 4-16 4-16 0ZM17 22c0 4 16 4 16 0M17 28c0 4 16 4 16 0"
    />
  {:else if node.assetKind === "Firewall"}
    <path class="canvas-node-glyph" d="M17 20h16v17H17zM17 26h16M25 20v17" />
  {:else}
    <path
      class="canvas-node-glyph"
      d="M17 20h16v7H17zM17 30h16v7H17zM21 23h.01M21 33h.01"
    />
  {/if}
  <text class="canvas-node-title" x="47" y="25">{node.name}</text>
  <text class="canvas-node-sub" x="47" y="42">{node.address}</text>
  <circle
    class={[
      "canvas-status-dot",
      node.critical ? "risk" : node.risk === "Low" ? "healthy" : "warning",
    ]}
    cx="16"
    cy="58"
    r="4"
  />
  <text class="canvas-node-sub" x="25" y="61">{node.status}</text>
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
  .canvas-node-icon-bg {
    fill: #e7f0fc;
  }
  .canvas-node.critical .canvas-node-icon-bg {
    fill: #ffe9e6;
  }
  .canvas-node-glyph {
    fill: none;
    stroke: #32669f;
    stroke-width: 1.7;
    pointer-events: none;
  }
  .canvas-node.critical .canvas-node-glyph {
    stroke: #b42318;
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
  .canvas-status-dot.risk {
    fill: #d04437;
  }
  .canvas-status-dot.healthy {
    fill: #2e8b57;
  }
  .canvas-status-dot.warning {
    fill: #d28a20;
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
