import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import SimulationReport from "./SimulationReport.svelte";
import { SimulationReportDocument } from "./SimulationReportDocument.svelte";
import type { SimulationReportData } from "../contract";

vi.mock(
  "./StatisticalChart.svelte",
  () =>
    // @ts-expect-error svelte-check does not generate declarations for test stubs.
    import("./StatisticalChartStub.svelte"),
);

afterEach(cleanup);

describe("SimulationReport", () => {
  it("opens the source graph without awaiting the callback", async () => {
    const onOpenSourceGraph = vi.fn(() => new Promise<boolean>(() => {}));
    const document = new SimulationReportDocument(
      "Topology",
      "graph-1",
      "revision-1",
    );

    render(SimulationReport, { props: { document, onOpenSourceGraph } });
    await fireEvent.click(
      screen.getByRole("button", { name: "Open source graph" }),
    );

    expect(onOpenSourceGraph).toHaveBeenCalledOnce();
  });

  it("shows required flow availability before an attack", () => {
    const document = new SimulationReportDocument(
      "Topology",
      "graph-1",
      "revision-1",
    );
    document.markReady("experiment-1");
    document.setReportData({
      experiment_id: "experiment-1",
      graph_id: "graph-1",
      graph_revision_id: "revision-1",
      graph_title: "Topology",
      iteration_count: 1,
      run_count: 1,
      total_runtime_ms: 1,
      feasible: false,
      capability_statuses: [
        {
          capability_id: "capability-1",
          operational: false,
          required_flow_count: 2,
          missing_flow_count: 1,
          supporting_host_count: 1,
          min_operational_support: 2,
        },
      ],
      graph: {
        id: "graph-1",
        title: "Topology",
        revision_id: "revision-1",
        parent_revision_id: null,
        revision_kind: "original",
        revision_number: 1,
        nodes: [
          {
            id: "segment-1",
            type: "NetworkSegment",
            data: { name: "Client" },
            view_data: { x_pos: 0, y_pos: 0 },
          },
          {
            id: "host-1",
            type: "Host",
            data: { name: "Browser" },
            view_data: { x_pos: 0, y_pos: 0 },
          },
          {
            id: "service-available",
            type: "Service",
            data: { name: "Order API", port: 443, protocol: "tcp" },
            view_data: { x_pos: 0, y_pos: 0 },
          },
          {
            id: "service-unavailable",
            type: "Service",
            data: { name: "Inventory API", port: 8443, protocol: "tcp" },
            view_data: { x_pos: 0, y_pos: 0 },
          },
          {
            id: "capability-1",
            type: "MissionCapability",
            data: {
              name: "Order entry",
              impact_weight: 1,
              min_operational_support: 2,
              required_flows: [
                {
                  source_segment_id: "segment-1",
                  target_service_id: "service-available",
                },
                {
                  source_segment_id: "segment-1",
                  target_service_id: "service-unavailable",
                },
              ],
            },
            view_data: { x_pos: 0, y_pos: 0 },
          },
        ],
        edges: [
          {
            id: "contains-1",
            type: "Contains",
            from_id: "segment-1",
            to_id: "host-1",
            data: {},
          },
        ],
      },
      charts: {
        action_success: [],
        capability_impact: [],
        cdf: [],
        convergence: [],
        edge_traversal: [],
        histogram: [],
        host_compromise: [],
      },
      operational_flows: [
        {
          id: "flow-1",
          from_id: "host-1",
          to_id: "service-available",
        },
      ],
      summary: {
        expected_blast_radius: 0,
        median_blast_radius: 0,
        blast_radius_p95: 0,
        blast_radius_p99: 0,
        min_blast_radius: 0,
        max_blast_radius: 0,
        blast_radius_variance: 0,
        host_count: 1,
        expected_mission_impact: 0,
        median_mission_impact: 0,
        mission_impact_p95: 0,
        mission_impact_p99: 0,
        min_mission_impact: 0,
        max_mission_impact: 0,
        mission_impact_variance: 0,
      },
    } as unknown as SimulationReportData);

    render(SimulationReport, { props: { document } });

    expect(
      screen.getByRole("heading", { name: "Pre-attack capability status" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("columnheader", {
        name: "Flows available / required",
      }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("columnheader", { name: "Required flows" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("columnheader", {
        name: "Supports available / minimum",
      }),
    ).toBeInTheDocument();
    expect(screen.getAllByText("1 / 2")).toHaveLength(2);
    expect(
      screen.getByRole("list", { name: "Required flows for Order entry" }),
    ).toHaveTextContent("Client to Order API:443: Available");
    expect(
      screen.getByRole("list", { name: "Required flows for Order entry" }),
    ).toHaveTextContent("Client to Inventory API:8443: Unavailable");
    expect(
      screen.getByText(
        "1 required flow unavailable; 1 supporting host required",
      ),
    ).toBeInTheDocument();
  });
});
