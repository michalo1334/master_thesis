import type { Node } from "../../contracts.generated/graph";
import type { TopologyProjection } from "../../contracts.generated/dashboard/graph";
import type { SimulationReportCharts } from "../../contracts.generated/dashboard/simulation";
import type {
  CanvasEdgeAppearance,
  CanvasNodeAppearance,
} from "../graph/canvas/appearance";
import type { TopologyConnectionBundle } from "../graph/unified/topology-bundles";

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

export function heatTone(probability: number): HeatTone {
  const index = Math.min(
    heatPalette.length - 1,
    Math.max(0, Math.floor(Math.max(0, Math.min(1, probability)) * 4)),
  );
  return heatPalette[index];
}

/**
 * Heat appearance for the unified topology canvas.
 *
 * Hosts use their compromise probability. A bundle uses the highest traversal
 * heat of its projected flow groups. A simulation traversal ID belongs to a
 * materialized operational flow and never to a policy edge. The same bundle
 * appears at every zoom level.
 */
export function simulationHeatmapAppearance(
  charts: SimulationReportCharts,
  projection?: TopologyProjection,
): {
  nodeAppearance: (node: Node) => CanvasNodeAppearance | undefined;
  bundleAppearance: (
    bundle: TopologyConnectionBundle,
  ) => CanvasEdgeAppearance | undefined;
} {
  const hostProbabilities = hostCompromiseProbabilities(charts);
  const edgeProbabilities = edgeTraversalProbabilities(charts);
  const policyHeat = policyTraversalHeat(projection, edgeProbabilities);

  return {
    nodeAppearance(node) {
      if (node.type !== "Host") return undefined;
      return nodeHeatAppearance(hostProbabilities.get(node.id));
    },
    bundleAppearance(bundle) {
      return edgeHeatAppearance(
        policyHeat.get(
          policySegmentKey(bundle.fromSegmentId, bundle.toSegmentId),
        ),
      );
    },
  };
}

/**
 * Highest traversal probability per directed segment bundle.
 *
 * The source and target segments come from projected host membership. Flow
 * groups that cross the same directed segment pair aggregate under one key. A
 * policy-only bundle has no heat of its own.
 */
function policyTraversalHeat(
  projection: TopologyProjection | undefined,
  edgeProbabilities: ReadonlyMap<string, number>,
): Map<string, number> {
  const segmentByHost = new Map(
    (projection?.hosts ?? []).map((host) => [host.id, host.segment_id]),
  );
  const heat = new Map<string, number>();
  for (const group of projection?.flow_groups ?? []) {
    const from = segmentByHost.get(group.source_host_id);
    const to = segmentByHost.get(group.target_host_id);
    if (!from || !to) continue;
    const probability = maxProbability(edgeProbabilities, group.flow_ids);
    if (probability === undefined) continue;
    const key = policySegmentKey(from, to);
    const current = heat.get(key);
    heat.set(
      key,
      current === undefined ? probability : Math.max(current, probability),
    );
  }
  return heat;
}

function policySegmentKey(fromSegmentId: string, toSegmentId: string): string {
  return `${fromSegmentId}:${toSegmentId}`;
}

function hostCompromiseProbabilities(
  charts: SimulationReportCharts,
): Map<string, number> {
  return new Map(
    charts.host_compromise.map(({ host_id, compromise_probability }) => [
      host_id,
      compromise_probability,
    ]),
  );
}

function edgeTraversalProbabilities(
  charts: SimulationReportCharts,
): Map<string, number> {
  return new Map(
    charts.edge_traversal.map(({ edge_id, traversal_probability }) => [
      edge_id,
      traversal_probability,
    ]),
  );
}

function maxProbability(
  probabilities: ReadonlyMap<string, number>,
  ids: readonly string[],
): number | undefined {
  let max: number | undefined;
  for (const id of ids) {
    const probability = probabilities.get(id);
    if (probability === undefined) continue;
    max = max === undefined ? probability : Math.max(max, probability);
  }
  return max;
}

function nodeHeatAppearance(
  probability: number | undefined,
): CanvasNodeAppearance | undefined {
  if (probability === undefined) return undefined;
  const tone = heatTone(probability);
  return { cardFill: tone.fill, cardStroke: tone.color, cardStrokeWidth: 2.5 };
}

function edgeHeatAppearance(
  probability: number | undefined,
): CanvasEdgeAppearance | undefined {
  if (probability === undefined) return undefined;
  const tone = heatTone(probability);
  return { opacity: 0.95, stroke: tone.color, strokeWidth: 3 };
}
