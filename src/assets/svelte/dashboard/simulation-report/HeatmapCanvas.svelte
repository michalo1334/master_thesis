<script lang="ts">
  import Canvas from "../graph/canvas/Canvas.svelte";
  import NetworkCanvas from "../graph/network/NetworkCanvas.svelte";
  import { projectNetwork } from "../graph/network/NetworkCanvasProjection";
  import {
    edgeIdsHeatAppearance,
    hostHeatAppearance,
    simulationHeatmapAppearance,
  } from "./heatmap";
  import type { SimulationReportDocument } from "./SimulationReportDocument.svelte";

  interface Props {
    document: SimulationReportDocument;
  }

  let { document }: Props = $props();
  let canvasMode = $state<"topology" | "network">("topology");

  let heatmapAppearance = $derived(
    document.reportData
      ? simulationHeatmapAppearance(document.reportData.charts)
      : undefined,
  );
  let heatmapFlows = $derived(
    document.heatmapGraph && document.reportData
      ? projectNetwork(
          document.heatmapGraph,
          document.reportData.operational_flows,
        ).operationalFlows
      : [],
  );
</script>

<div class="heatmap-canvas">
  <div class="canvas-mode-toggle" role="group" aria-label="Heatmap view">
    <button
      type="button"
      aria-pressed={canvasMode === "topology"}
      onclick={() => (canvasMode = "topology")}>Topology</button
    >
    <button
      type="button"
      aria-pressed={canvasMode === "network"}
      onclick={() => (canvasMode = "network")}>Network</button
    >
  </div>

  {#if canvasMode === "topology"}
    {#if document.heatmapGraph}
      <Canvas
        graph={document.heatmapGraph}
        nodeAppearance={heatmapAppearance?.nodeAppearance}
        edgeAppearance={heatmapAppearance?.edgeAppearance}
        structuralFlows={heatmapFlows}
        structuralFlowAppearance={heatmapAppearance?.flowAppearance}
        selectedNodeId={document.heatmapSelectedNodeId}
        selectedEdgeId={document.heatmapSelectedEdgeId}
        onGraphChange={(graph) => (document.heatmapGraph = graph)}
        onSelectNode={(nodeId) => document.selectHeatmapNode(nodeId)}
        onSelectEdge={(edgeId) => document.selectHeatmapEdge(edgeId)}
        onClearSelection={() => document.clearHeatmapSelection()}
        ariaLabel="Simulation attack-path heatmap"
      />
    {/if}
  {:else if document.heatmapGraph && document.reportData}
    <NetworkCanvas
      graph={document.heatmapGraph}
      operationalFlows={document.reportData.operational_flows}
      selectedNodeId={document.heatmapSelectedNodeId}
      selectedEdgeId={document.heatmapSelectedEdgeId}
      onSelectNode={(nodeId) => document.selectHeatmapNode(nodeId)}
      onSelectEdge={(edgeId) => document.selectHeatmapEdge(edgeId)}
      onGraphChange={(graph) => (document.heatmapGraph = graph)}
      hostAppearance={(hostId) =>
        hostHeatAppearance(document.reportData!.charts, hostId)}
      policyLinkAppearance={(link) =>
        edgeIdsHeatAppearance(document.reportData!.charts, link.edgeIds)}
      operationalFlowAppearance={(flow) =>
        edgeIdsHeatAppearance(document.reportData!.charts, flow.flowIds)}
    />
  {/if}
</div>

<style>
  .heatmap-canvas {
    position: relative;
    height: 100%;
    min-height: 0;
  }
  .canvas-mode-toggle {
    position: absolute;
    z-index: 2;
    top: var(--ds-space-3);
    left: var(--ds-space-3);
    display: flex;
    overflow: hidden;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
  }
  .canvas-mode-toggle button {
    min-height: 2rem;
    border: 0;
    border-right: 1px solid var(--ds-color-border);
    background: transparent;
    color: var(--ds-color-text-secondary);
    padding: 0 0.625rem;
  }
  .canvas-mode-toggle button:last-child {
    border-right: 0;
  }
  .canvas-mode-toggle button[aria-pressed="true"] {
    background: var(--ds-color-accent-soft);
    color: var(--ds-color-text);
    font-weight: 700;
  }
</style>
