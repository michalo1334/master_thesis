import type { Edge, Node } from "../contract";
import type { SimulationReportCharts } from "../../contracts.generated";
import type {
  CanvasEdgeAppearance,
  CanvasNodeAppearance,
  CanvasStructuralFlow,
} from "../graph/canvas/appearance";

export interface HeatmapLegendItem {
  color: string;
  label: string;
}

interface HeatTone extends HeatmapLegendItem {
  fill: string;
}

const heatPalette: readonly HeatTone[] = [
  { label: "Low (0–24%)", color: "#15803d", fill: "#dcfce7" },
  { label: "Moderate (25–49%)", color: "#ca8a04", fill: "#fef9c3" },
  { label: "High (50–74%)", color: "#ea580c", fill: "#ffedd5" },
  { label: "Critical (75–100%)", color: "#b91c1c", fill: "#fee2e2" },
];

export const heatmapLegend: readonly HeatmapLegendItem[] = heatPalette;

function heatTone(probability: number): HeatTone {
  const index = Math.min(
    heatPalette.length - 1,
    Math.max(0, Math.floor(Math.max(0, Math.min(1, probability)) * 4)),
  );
  return heatPalette[index];
}

export function simulationHeatmapAppearance(charts: SimulationReportCharts): {
  edgeAppearance: (edge: Edge) => CanvasEdgeAppearance | undefined;
  flowAppearance: (
    flow: CanvasStructuralFlow,
  ) => CanvasEdgeAppearance | undefined;
  nodeAppearance: (node: Node) => CanvasNodeAppearance | undefined;
} {
  const hostProbabilities = new Map(
    charts.host_compromise.map(({ host_id, compromise_probability }) => [
      host_id,
      compromise_probability,
    ]),
  );
  const edgeProbabilities = new Map(
    charts.edge_traversal.map(({ edge_id, traversal_probability }) => [
      edge_id,
      traversal_probability,
    ]),
  );

  return {
    nodeAppearance(node) {
      const probability = hostProbabilities.get(node.id);
      if (node.type !== "Host" || probability === undefined) return undefined;

      const tone = heatTone(probability);
      return {
        cardFill: tone.fill,
        cardStroke: tone.color,
        cardStrokeWidth: 2.5,
      };
    },
    edgeAppearance(edge) {
      return appearanceForEdge(edge.id);
    },
    flowAppearance(flow) {
      return appearanceForEdge(flow.id);
    },
  };

  function appearanceForEdge(id: string): CanvasEdgeAppearance | undefined {
    const probability = edgeProbabilities.get(id);
    if (probability === undefined) return undefined;

    const tone = heatTone(probability);
    return { opacity: 0.95, stroke: tone.color, strokeWidth: 3 };
  }
}
