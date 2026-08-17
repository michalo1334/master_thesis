import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import MissionCapabilityInspector from "./MissionCapabilityInspector.svelte";
import type { DashboardApi } from "../../dashboard-api";
import type { LoadedGraph } from "../../contract";

afterEach(cleanup);

const graph = {
  id: "graph-1",
  title: "Topology",
  revision_id: "revision-1",
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
      id: "service-1",
      type: "Service",
      data: { name: "API", port: 443, protocol: "tcp" },
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
} satisfies LoadedGraph;

describe("MissionCapabilityInspector", () => {
  it("shows labels for selected required flows", () => {
    render(MissionCapabilityInspector, {
      props: {
        selectable: {
          id: "capability-1",
          type: "MissionCapability",
          data: {
            name: "Order entry",
            impact_weight: 1,
            min_operational_support: 1,
            required_flows: [
              {
                source_segment_id: "segment-1",
                target_service_id: "service-1",
              },
            ],
          },
          view_data: { x_pos: 0, y_pos: 0 },
        },
        graph,
        api: {} as DashboardApi,
        canEditFlows: false,
        onUpdate: vi.fn(),
      },
    });

    expect(screen.getByText("1 selected")).toBeInTheDocument();
    expect(
      screen.getByRole("list", { name: "Selected required flows" }),
    ).toHaveTextContent("Client to API:443");
  });

  it("selects required flows from the saved graph projection", async () => {
    const onUpdate = vi.fn();
    const api = {
      fetchGraphProjection: vi.fn().mockResolvedValue({
        status: "ok",
        operational_flows: [
          { id: "flow-1", from_id: "host-1", to_id: "service-1" },
        ],
      }),
    } as unknown as DashboardApi;

    render(MissionCapabilityInspector, {
      props: {
        selectable: {
          id: "capability-1",
          type: "MissionCapability",
          data: {
            name: "Order entry",
            impact_weight: 1,
            min_operational_support: 1,
            required_flows: [],
          },
          view_data: { x_pos: 0, y_pos: 0 },
        },
        graph,
        api,
        revisionId: "revision-1",
        canEditFlows: true,
        onUpdate,
      },
    });

    await waitFor(() =>
      expect(api.fetchGraphProjection).toHaveBeenCalledWith("revision-1"),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Change required flows" }),
    );
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select segment-1:service-1" }),
    );
    await fireEvent.click(screen.getByRole("button", { name: "Select (1)" }));

    expect(onUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          required_flows: [
            { source_segment_id: "segment-1", target_service_id: "service-1" },
          ],
        }),
      }),
    );
  });
});
