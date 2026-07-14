<script lang="ts">
  import { DropdownMenu } from "bits-ui";
  import Icon from "./Icon.svelte";
  import { topologyEdges, topologyNodes } from "./data";
  import type { DashboardDocument, ViewMode } from "./types";

  interface Props {
    document: DashboardDocument;
    selectedNodeId: string;
    view: ViewMode;
    zoom: number;
    inspectorOpen: boolean;
    onSelectNode: (id: string) => void;
    onViewChange: (view: ViewMode) => void;
    onZoomChange: (zoom: number) => void;
    onRestoreInspector: () => void;
  }

  let {
    document, selectedNodeId, view, zoom, inspectorOpen, onSelectNode, onViewChange,
    onZoomChange, onRestoreInspector
  }: Props = $props();

  let viewportTransform = $derived(`translate(560 325) scale(${zoom / 100}) translate(-560 -325)`);

  function handleNodeKeydown(event: KeyboardEvent, id: string) {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    onSelectNode(id);
  }
</script>

<div class="dashboard-canvas-shell" role="tabpanel" aria-label={`${document.title} canvas`}>
  <div class="dashboard-canvas-toolbar" aria-label="Canvas tools">
    <button class="dashboard-tool-button" aria-label="Graph view" aria-pressed={view === "graph"} onclick={() => onViewChange("graph")}><Icon name="graph" /></button>
    <button class="dashboard-tool-button" aria-label="List view" aria-pressed={view === "list"} onclick={() => onViewChange("list")}><Icon name="list" /></button>
    <button class="dashboard-tool-button" aria-label="Fit to screen" onclick={() => onZoomChange(100)}><Icon name="fit" /></button>
    <DropdownMenu.Root>
      <DropdownMenu.Trigger class="dashboard-tool-button" aria-label="More canvas actions"><Icon name="more" /></DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content class="dashboard-menu-content" sideOffset={7} align="start">
          <DropdownMenu.Group aria-label="Canvas actions">
            <DropdownMenu.GroupHeading class="dashboard-menu-heading">Canvas</DropdownMenu.GroupHeading>
            <DropdownMenu.Item class="dashboard-menu-item" onclick={() => onViewChange("graph")}><Icon name="graph" size={16} />Graph view</DropdownMenu.Item>
            <DropdownMenu.Item class="dashboard-menu-item" onclick={() => onViewChange("list")}><Icon name="list" size={16} />List view</DropdownMenu.Item>
            <DropdownMenu.Item class="dashboard-menu-item" onclick={() => onZoomChange(100)}><Icon name="fit" size={16} />Fit topology</DropdownMenu.Item>
          </DropdownMenu.Group>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  </div>

  {#if view === "graph"}
    <svg class="dashboard-graph" viewBox="0 0 1120 650" role="group" aria-labelledby="topology-title topology-description">
      <title id="topology-title">{document.title}</title>
      <desc id="topology-description">Network topology with external, DMZ, application, and data zones. Tab to select an asset.</desc>
      <defs>
        <filter id="dashboard-node-shadow" x="-20%" y="-25%" width="140%" height="160%"><feDropShadow dx="0" dy="2" stdDeviation="2" flood-color="#17243c" flood-opacity=".16"/></filter>
        <marker id="dashboard-arrow" markerWidth="8" markerHeight="8" refX="7" refY="3" orient="auto"><path d="M0 0 8 3 0 6Z" fill="#718197"/></marker>
        <marker id="dashboard-arrow-warning" markerWidth="8" markerHeight="8" refX="7" refY="3" orient="auto"><path d="M0 0 8 3 0 6Z" fill="#c77a19"/></marker>
      </defs>
      <g transform={viewportTransform}>
        <g aria-hidden="true">
          <rect class="dashboard-zone" x="34" y="52" width="188" height="520" rx="12"/><text class="dashboard-zone-title" x="50" y="78">EXTERNAL</text>
          <rect class="dashboard-zone" x="254" y="52" width="250" height="520" rx="12"/><text class="dashboard-zone-title" x="270" y="78">DMZ · VLAN 10</text>
          <rect class="dashboard-zone" x="536" y="52" width="284" height="520" rx="12"/><text class="dashboard-zone-title" x="552" y="78">APPLICATION · VLAN 20</text>
          <rect class="dashboard-zone" x="852" y="52" width="234" height="520" rx="12"/><text class="dashboard-zone-title" x="868" y="78">DATA · VLAN 30</text>
        </g>
        <g aria-hidden="true">
          {#each topologyEdges as edge (edge.id)}
            <g>
              <path class={["dashboard-edge-line", edge.warning && "warning"]} d={edge.path}/>
              <text class="dashboard-edge-label" x={edge.labelX} y={edge.labelY}>{edge.label}</text>
            </g>
          {/each}
        </g>
        <g>
          {#each topologyNodes as node (node.id)}
            <g
              class={["dashboard-node", node.critical && "critical", node.id === selectedNodeId && "selected"]}
              transform={`translate(${node.x} ${node.y})`}
              tabindex="0"
              role="button"
              aria-label={`${node.name}, ${node.kind}, ${node.risk} risk${node.id === selectedNodeId ? ", selected" : ""}`}
              onclick={() => onSelectNode(node.id)}
              onkeydown={(event) => handleNodeKeydown(event, node.id)}
            >
              <rect class="dashboard-node-card" width="120" height="72" rx="7"/>
              <circle class="dashboard-node-icon-bg" cx="25" cy="28" r="15"/>
              <path class="dashboard-node-glyph" d={node.kind.includes("Database") || node.kind.includes("Data") ? "M17 22c0-4 16-4 16 0v13c0 4-16 4-16 0ZM17 22c0 4 16 4 16 0M17 28c0 4 16 4 16 0" : "M17 20h16v7H17zM17 30h16v7H17zM21 23h.01M21 33h.01"}/>
              <text class="dashboard-node-title" x="47" y="25">{node.name}</text>
              <text class="dashboard-node-sub" x="47" y="42">{node.address}</text>
              <circle class={["dashboard-status-dot", node.critical ? "risk" : node.risk === "Low" ? "healthy" : "warning"]} cx="16" cy="58" r="4"/>
              <text class="dashboard-node-sub" x="25" y="61">{node.status}</text>
            </g>
          {/each}
        </g>
      </g>
    </svg>
    <div class="dashboard-canvas-hint">Select an asset to inspect its properties</div>
  {:else}
    <div class="dashboard-list-view">
      <table aria-label="Topology assets">
        <thead><tr><th>Asset</th><th>Address</th><th>Zone</th><th>Risk</th><th>Connections</th></tr></thead>
        <tbody>
          {#each topologyNodes as node (node.id)}
            <tr class={[node.id === selectedNodeId && "selected"]}>
              <td><button class="dashboard-table-select" onclick={() => onSelectNode(node.id)}>{node.name}</button></td>
              <td>{node.address}</td><td>{node.zone}</td><td><span class={["dashboard-risk-tag", node.critical && "critical"]}>{node.risk}</span></td><td>{node.connections}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}

  {#if !inspectorOpen}
    <button class="dashboard-inspector-restore" aria-controls="dashboard-property-inspector" aria-expanded="false" onclick={onRestoreInspector}>Show properties</button>
  {/if}
  <div class="dashboard-zoom" aria-label="Canvas zoom">
    <button aria-label="Zoom out" onclick={() => onZoomChange(zoom - 10)}><Icon name="minus" size={16} /></button>
    <output>{zoom}%</output>
    <button aria-label="Zoom in" onclick={() => onZoomChange(zoom + 10)}><Icon name="plus" size={16} /></button>
  </div>
</div>

<style>
  .dashboard-canvas-shell { position: relative; height: 100%; min-height: 0; overflow: hidden; background-color: var(--ds-color-canvas); background-image: linear-gradient(#cbd3dd55 1px, transparent 1px), linear-gradient(90deg, #cbd3dd55 1px, transparent 1px), linear-gradient(#b6c1ce44 1px, transparent 1px), linear-gradient(90deg, #b6c1ce44 1px, transparent 1px); background-size: 20px 20px, 20px 20px, 100px 100px, 100px 100px; }
  .dashboard-canvas-toolbar { position: absolute; z-index: 2; top: 0.625rem; left: var(--ds-space-3); display: flex; background: var(--ds-color-paper); border: 1px solid #b9c3cf; border-radius: 0.3125rem; box-shadow: var(--ds-shadow-md); }
  .dashboard-tool-button { min-width: 2.125rem; min-height: var(--ds-document-tab-height); padding: 0; border: 0; border-right: 1px solid var(--ds-color-border-soft); background: var(--ds-color-paper); display: grid; place-items: center; }
  .dashboard-tool-button:hover, .dashboard-tool-button[aria-pressed="true"] { background: var(--ds-color-accent-soft); color: var(--ds-color-accent); }
  .dashboard-graph { width: 100%; height: 100%; display: block; }
  .dashboard-zone { fill: #f9fbfdc9; stroke: #8796a9; stroke-width: 1.2; stroke-dasharray: 6 4; }
  .dashboard-zone-title { font-size: var(--ds-text-sm); font-weight: 700; fill: #647286; letter-spacing: 0.03125rem; }
  .dashboard-edge-line { fill: none; stroke: #718197; stroke-width: 2; marker-end: url(#dashboard-arrow); }
  .dashboard-edge-line.warning { stroke: #c77a19; stroke-dasharray: 6 3; marker-end: url(#dashboard-arrow-warning); }
  .dashboard-edge-label { font-size: var(--ds-text-xs); fill: var(--ds-color-text-secondary); paint-order: stroke; stroke: #edf1f5; stroke-width: 4px; stroke-linejoin: round; }
  .dashboard-node { cursor: pointer; }
  .dashboard-node-card { fill: #fff; stroke: #8090a4; stroke-width: 1.2; filter: url(#dashboard-node-shadow); }
  .dashboard-node.selected .dashboard-node-card { stroke: #0b6fe8; stroke-width: 3; }
  .dashboard-node-icon-bg { fill: #e7f0fc; }
  .dashboard-node.critical .dashboard-node-icon-bg { fill: #ffe9e6; }
  .dashboard-node-glyph { fill: none; stroke: #32669f; stroke-width: 1.7; pointer-events: none; }
  .dashboard-node.critical .dashboard-node-glyph { stroke: #b42318; }
  .dashboard-node-title { font-size: var(--ds-text-sm); font-weight: 700; fill: #1b2738; pointer-events: none; }
  .dashboard-node-sub { font: var(--ds-text-xs) var(--ds-font-mono); fill: var(--ds-color-text-muted); pointer-events: none; }
  .dashboard-status-dot.risk { fill: #d04437; }
  .dashboard-status-dot.healthy { fill: #2e8b57; }
  .dashboard-status-dot.warning { fill: #d28a20; }
  .dashboard-canvas-hint { position: absolute; left: var(--ds-space-3); bottom: var(--ds-space-3); padding: 0.3125rem var(--ds-space-2); border: 1px solid #c7d0da; border-radius: var(--ds-radius-md); background: #ffffffd9; color: #5d6a7d; font-size: var(--ds-text-xs); }
  .dashboard-zoom { position: absolute; right: var(--ds-space-3); bottom: var(--ds-space-3); display: flex; align-items: center; border: 1px solid #b9c3cf; border-radius: 0.3125rem; background: var(--ds-color-paper); box-shadow: var(--ds-shadow-md); }
  .dashboard-zoom button { width: 1.9375rem; min-height: 1.8125rem; border: 0; background: transparent; display: grid; place-items: center; }
  .dashboard-zoom button:hover { background: var(--ds-color-accent-soft); }
  .dashboard-zoom output { min-width: 3rem; text-align: center; font: var(--ds-text-sm) var(--ds-font-mono); font-variant-numeric: tabular-nums; }
  .dashboard-inspector-restore { position: absolute; z-index: 4; right: 0.625rem; top: 0.625rem; min-height: var(--ds-document-tab-height); padding: 0 0.625rem; border: 1px solid #aeb9c7; border-radius: var(--ds-radius-md); background: var(--ds-color-paper); box-shadow: var(--ds-shadow-md); }

  .dashboard-list-view { height: 100%; overflow: auto; padding: 3.375rem 1.25rem 1.25rem; }
  .dashboard-list-view table { width: 100%; border-collapse: collapse; background: var(--ds-color-paper); border: 1px solid var(--ds-color-border); box-shadow: 0 2px 6px #17243c12; }
  .dashboard-list-view th, .dashboard-list-view td { padding: 0.625rem var(--ds-space-3); text-align: left; border-bottom: 1px solid var(--ds-color-border-soft); }
  .dashboard-list-view th { color: #526176; background: #f6f8fa; font-size: var(--ds-text-xs); text-transform: uppercase; letter-spacing: 0.025rem; }
  .dashboard-list-view tr.selected, .dashboard-list-view tr:hover { background: var(--ds-color-accent-soft); }
  .dashboard-table-select { padding: 0; border: 0; background: transparent; color: var(--ds-color-accent); font-weight: 600; }
  .dashboard-risk-tag { display: inline-flex; align-items: center; min-height: 1.375rem; padding: 0 0.4375rem; border-radius: 0.625rem; color: #7b5418; background: #fff1d7; font-size: var(--ds-text-xs); font-weight: 600; }
  .dashboard-risk-tag.critical { color: #8d2c24; background: #fde9e7; }

  @media (forced-colors: active) {
    .dashboard-node-card, .dashboard-zone, .dashboard-canvas-toolbar, .dashboard-zoom { forced-color-adjust: auto; }
    .dashboard-node.selected .dashboard-node-card { outline: 2px solid Highlight; }
    .dashboard-status-dot { fill: CanvasText; }
  }
</style>
