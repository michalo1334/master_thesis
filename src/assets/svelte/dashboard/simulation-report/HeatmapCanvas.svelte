<script lang="ts">
  import TopologyCanvas from "../graph/unified/TopologyCanvas.svelte";
  import { simulationHeatmapAppearance } from "./heatmap";
  import type { SimulationReportDocument } from "./SimulationReportDocument.svelte";

  interface Props {
    document: SimulationReportDocument;
  }

  let { document }: Props = $props();

  let projection = $derived(document.topologyProjection);
  let appearance = $derived(
    document.reportData
      ? simulationHeatmapAppearance(
          document.reportData.charts,
          projection ?? undefined,
        )
      : undefined,
  );
</script>

<div class="heatmap-canvas">
  {#if document.heatmapGraph && projection && appearance}
    <TopologyCanvas
      graph={document.heatmapGraph}
      {projection}
      readOnly
      nodeAppearance={appearance.nodeAppearance}
      policyAppearance={appearance.policyAppearance}
      flowAppearance={appearance.flowAppearance}
      selectedNodeId={document.heatmapSelectedNodeId}
      selectedEdgeId={document.heatmapSelectedEdgeId}
      onSelectNode={(nodeId) => document.selectHeatmapNode(nodeId)}
      onSelectEdge={(edgeId) => document.selectHeatmapEdge(edgeId)}
      onClearSelection={() => document.clearHeatmapSelection()}
      ariaLabel="Simulation attack-path heatmap"
    />
  {:else}
    <p class="heatmap-unavailable" role="status">
      Topology grouping is unavailable for this report.
    </p>
  {/if}
</div>

<style>
  .heatmap-canvas {
    position: relative;
    height: 100%;
    min-height: 0;
  }
  .heatmap-unavailable {
    margin: 0;
    color: var(--ui-color-warning-text);
    font-size: var(--ui-text-sm);
  }
</style>
