import { expect, it } from "vitest";
import type { SimulationReportCharts } from "../../contracts.generated";
import { simulationHeatmapAppearance } from "./heatmap";

it("styles reported hosts and traversed edges from their probabilities", () => {
  const charts: SimulationReportCharts = {
    action_success: [],
    cdf: [],
    convergence: [],
    edge_traversal: [{ edge_id: "edge-1", traversal_probability: 0.8 }],
    histogram: [],
    host_compromise: [{ host_id: "host-1", compromise_probability: 0.6 }],
  };
  const appearance = simulationHeatmapAppearance(charts);

  expect(
    appearance.nodeAppearance({
      id: "host-1",
      type: "Host",
      data: { name: "Host" },
      view_data: { x_pos: 0, y_pos: 0 },
    }),
  ).toMatchObject({ cardFill: "#ffedd5", cardStroke: "#ea580c" });
  expect(
    appearance.edgeAppearance({
      id: "edge-1",
      type: "Runs",
      data: {},
      from_id: "host-1",
      to_id: "host-2",
    }),
  ).toMatchObject({ stroke: "#b91c1c", strokeWidth: 3 });
});
