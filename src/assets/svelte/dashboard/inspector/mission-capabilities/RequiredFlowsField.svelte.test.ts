import type { MissionCapabilityNode } from "../../../contracts.generated/graph";
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import RequiredFlowsField from "./RequiredFlowsField.svelte";
import {
  flowGroupRecord,
  graphContract,
  hostRecord,
  projectionOf,
  segmentNode,
  serviceNode,
  serviceRecord,
} from "../../graph/__tests__/topology-fixtures";

afterEach(cleanup);

const graph = graphContract([
  segmentNode("segment-1"),
  serviceNode("service-1"),
  serviceNode("service-2"),
]);

function missionCapability(
  requiredFlows: MissionCapabilityNode["data"]["required_flows"],
): MissionCapabilityNode {
  return {
    id: "capability-1",
    type: "MissionCapability",
    data: {
      name: "Order entry",
      description: null,
      impact_weight: 1,
      min_operational_support: 1,
      required_flows: requiredFlows,
    },
    view_data: { x_pos: 0, y_pos: 0 },
  };
}

function projectionOffering(
  serviceId: string,
): ReturnType<typeof projectionOf> {
  return projectionOf({
    hosts: [hostRecord("host-1", "segment-1", [serviceId])],
    services: [serviceRecord(serviceId, "host-1")],
    flow_groups: [flowGroupRecord("host-1", "host-1", [serviceId], ["flow-1"])],
  });
}

describe("RequiredFlowsField", () => {
  it("keeps required flows that a missing projection cannot confirm", async () => {
    const onUpdate = vi.fn();
    const selectable = missionCapability([
      { source_segment_id: "segment-1", target_service_id: "service-1" },
    ]);

    render(RequiredFlowsField, {
      props: { selectable, graph, canEditFlows: true, onUpdate },
    });

    expect(screen.getByRole("status")).toHaveTextContent(
      "Reachable flows are unknown without an accepted projection.",
    );

    await fireEvent.click(
      screen.getByRole("button", { name: "Change required flows" }),
    );
    await fireEvent.click(screen.getByRole("button", { name: /Select/ }));

    expect(onUpdate).toHaveBeenCalledTimes(1);
    expect(onUpdate.mock.calls[0]![0]).toMatchObject({
      data: {
        required_flows: [
          { source_segment_id: "segment-1", target_service_id: "service-1" },
        ],
      },
    });
  });

  it("keeps an unoffered flow while adding an offered one", async () => {
    const onUpdate = vi.fn();
    const selectable = missionCapability([
      { source_segment_id: "segment-1", target_service_id: "service-1" },
    ]);

    render(RequiredFlowsField, {
      props: {
        selectable,
        graph,
        projection: projectionOffering("service-2"),
        canEditFlows: true,
        onUpdate,
      },
    });

    await fireEvent.click(
      screen.getByRole("button", { name: "Change required flows" }),
    );
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select segment-1:service-2" }),
    );
    await fireEvent.click(screen.getByRole("button", { name: /Select/ }));

    expect(onUpdate).toHaveBeenCalledTimes(1);
    expect(onUpdate.mock.calls[0]![0]).toMatchObject({
      data: {
        required_flows: [
          { source_segment_id: "segment-1", target_service_id: "service-2" },
          { source_segment_id: "segment-1", target_service_id: "service-1" },
        ],
      },
    });
  });

  it("offers each reachable segment-service pair once", async () => {
    const selectable = missionCapability([]);
    const projection = projectionOf({
      hosts: [
        hostRecord("host-1", "segment-1", ["service-1"]),
        hostRecord("host-2", "segment-1"),
      ],
      services: [serviceRecord("service-1", "host-1")],
      flow_groups: [
        flowGroupRecord("host-1", "host-1", ["service-1"], ["flow-1"]),
        flowGroupRecord("host-2", "host-1", ["service-1"], ["flow-2"]),
      ],
    });

    render(RequiredFlowsField, {
      props: {
        selectable,
        graph,
        projection,
        canEditFlows: true,
        onUpdate: vi.fn(),
      },
    });

    await fireEvent.click(
      screen.getByRole("button", { name: "Change required flows" }),
    );

    expect(screen.getAllByText("service-1:8080")).toHaveLength(1);
  });
});
