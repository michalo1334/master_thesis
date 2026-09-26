import type {
  Edge,
  GraphContract,
  Node,
} from "../../../contracts.generated/graph";
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import SelectionInspector from "./SelectionInspector.svelte";
import {
  flowGroupRecord,
  hostRecord,
  issueRecord,
  projectionOf,
  segmentRecord,
  serviceRecord,
} from "../../graph/__tests__/topology-fixtures";

afterEach(cleanup);

const graph: GraphContract = {
  id: "graph-a",
  title: "Graph",
  revision_id: "revision-a",
  parent_revision_id: null,
  revision_kind: "original",
  revision_number: 1,
  nodes: [],
  edges: [],
};
const baseProps = { graph, canEditFlows: false };

describe("SelectionInspector", () => {
  it("updates scalar data while preserving identity and view data", async () => {
    const onUpdate = vi.fn();
    const selectable = {
      id: "host-a",
      type: "Host",
      data: { name: "Host A" },
      view_data: { x_pos: 4, y_pos: 7 },
    } satisfies Node;
    render(SelectionInspector, {
      props: { ...baseProps, selectable, onUpdate },
    });
    await fireEvent.change(screen.getByLabelText("name"), {
      target: { value: "Host B" },
    });
    expect(onUpdate).toHaveBeenCalledWith({
      ...selectable,
      data: { name: "Host B" },
    });
  });

  it("renders generated enum choices and converts number text", async () => {
    const onUpdate = vi.fn();
    const selectable = {
      id: "service-a",
      type: "Service",
      data: { name: "API", port: 443, protocol: "tcp", version: null },
      view_data: { x_pos: 0, y_pos: 0 },
    } satisfies Node;
    render(SelectionInspector, {
      props: { ...baseProps, selectable, onUpdate },
    });
    expect(screen.getByLabelText("protocol")).toBeInTheDocument();
    await fireEvent.change(screen.getByLabelText("port"), {
      target: { value: "8080" },
    });
    expect(onUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { name: "API", port: 8080, protocol: "tcp", version: null },
      }),
    );
  });

  it("renders nested contract fields", () => {
    const selectable = {
      id: "vulnerability-a",
      type: "Vulnerability",
      data: {
        identifier: "CVE",
        exploit_probability: 0.4,
        cvss: {
          attack_vector: "network",
          attack_complexity: "low",
          privileges_required: "none",
          user_interaction: "none",
          scope: "unchanged",
          confidentiality_impact: "high",
          integrity_impact: "high",
          availability_impact: "high",
        },
      },
      view_data: { x_pos: 0, y_pos: 0 },
    } satisfies Node;
    render(SelectionInspector, {
      props: { ...baseProps, selectable, onUpdate: vi.fn() },
    });
    expect(screen.getByLabelText("cvss · attack vector")).toBeInTheDocument();
  });

  it("skips nested fields when their object is null", () => {
    const selectable = {
      id: "vulnerability-a",
      type: "Vulnerability",
      data: { identifier: "CVE", exploit_probability: 0.4, cvss: null },
      view_data: { x_pos: 0, y_pos: 0 },
    } as unknown as Node;
    render(SelectionInspector, {
      props: { ...baseProps, selectable, onUpdate: vi.fn() },
    });
    expect(screen.queryByLabelText("cvss · attack vector")).toBeNull();
  });

  it("converts an empty nullable value to null", async () => {
    const onUpdate = vi.fn();
    const selectable = {
      id: "service-a",
      type: "Service",
      data: { name: "API", port: 443, protocol: "tcp", version: "1.0" },
      view_data: { x_pos: 0, y_pos: 0 },
    } satisfies Node;
    render(SelectionInspector, {
      props: { ...baseProps, selectable, onUpdate },
    });
    await fireEvent.change(screen.getByLabelText("version"), {
      target: { value: "" },
    });
    expect(onUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ version: null }),
      }),
    );
  });

  it("renders a server validation error at its matching field", () => {
    const selectable = {
      id: "host-a",
      type: "Host",
      data: { name: "" },
      view_data: { x_pos: 4, y_pos: 7 },
    } satisfies Node;
    render(SelectionInspector, {
      props: {
        ...baseProps,
        selectable,
        errors: [
          {
            entity_kind: "node",
            entity_id: selectable.id,
            field_path: ["name"],
            message: "can't be blank",
          },
        ],
        onUpdate: vi.fn(),
      },
    });
    expect(screen.getByRole("alert")).toHaveTextContent("can't be blank");
    expect(screen.getByLabelText("name")).toHaveAttribute(
      "aria-invalid",
      "true",
    );
  });

  it("marks an invalid enum control and describes it with its errors", () => {
    const selectable = {
      id: "service-a",
      type: "Service",
      data: { name: "API", port: 443, protocol: "tcp", version: null },
      view_data: { x_pos: 0, y_pos: 0 },
    } satisfies Node;
    render(SelectionInspector, {
      props: {
        ...baseProps,
        selectable,
        errors: [
          {
            entity_kind: "node",
            entity_id: selectable.id,
            field_path: ["protocol"],
            message: "is unsupported",
          },
        ],
        onUpdate: vi.fn(),
      },
    });
    const control = screen.getByLabelText("protocol");
    expect(control).toHaveAttribute("aria-invalid", "true");
    expect(control).toHaveAttribute(
      "aria-describedby",
      screen.getByRole("alert").id,
    );
  });

  it("renders all matching errors and required-flow errors", () => {
    const selectable = {
      id: "capability-a",
      type: "MissionCapability",
      data: {
        name: "Capability",
        description: null,
        impact_weight: 1,
        min_operational_support: 1,
        required_flows: [],
      },
      view_data: { x_pos: 0, y_pos: 0 },
    } satisfies Node;
    render(SelectionInspector, {
      props: {
        ...baseProps,
        selectable,
        errors: [
          {
            entity_kind: "node",
            entity_id: selectable.id,
            field_path: ["name"],
            message: "first error",
          },
          {
            entity_kind: "node",
            entity_id: selectable.id,
            field_path: ["name"],
            message: "second error",
          },
          {
            entity_kind: "node",
            entity_id: selectable.id,
            field_path: ["required_flows"],
            message: "flow error",
          },
        ],
        onUpdate: vi.fn(),
      },
    });
    expect(screen.getByText("first error")).toBeInTheDocument();
    expect(screen.getByText("second error")).toBeInTheDocument();
    expect(screen.getByText("flow error")).toBeInTheDocument();
    expect(screen.getAllByRole("alert")).toHaveLength(2);
  });

  it("renders nested required-flow errors at the custom field", () => {
    const selectable = {
      id: "capability-a",
      type: "MissionCapability",
      data: {
        name: "Capability",
        description: null,
        impact_weight: 1,
        min_operational_support: 1,
        required_flows: [],
      },
      view_data: { x_pos: 0, y_pos: 0 },
    } satisfies Node;
    render(SelectionInspector, {
      props: {
        ...baseProps,
        selectable,
        errors: [
          {
            entity_kind: "node",
            entity_id: selectable.id,
            field_path: ["required_flows", "0", "source_segment_id"],
            message: "is invalid",
          },
        ],
        onUpdate: vi.fn(),
      },
    });
    expect(screen.getByRole("alert")).toHaveTextContent("is invalid");
  });

  it("does not update an empty non-nullable number", async () => {
    const onUpdate = vi.fn();
    const selectable = {
      id: "service-a",
      type: "Service",
      data: { name: "API", port: 443, protocol: "tcp", version: null },
      view_data: { x_pos: 0, y_pos: 0 },
    } satisfies Node;
    render(SelectionInspector, {
      props: { ...baseProps, selectable, onUpdate },
    });
    await fireEvent.change(screen.getByLabelText("port"), {
      target: { value: "" },
    });
    expect(onUpdate).not.toHaveBeenCalled();
  });

  it("uses the custom required-flow field and hides no raw list input", () => {
    const selectable = {
      id: "capability-a",
      type: "MissionCapability",
      data: {
        name: "Capability",
        description: null,
        impact_weight: 1,
        min_operational_support: 1,
        required_flows: [],
      },
      view_data: { x_pos: 0, y_pos: 0 },
    } satisfies Node;
    render(SelectionInspector, {
      props: { ...baseProps, selectable, onUpdate: vi.fn() },
    });
    expect(
      screen.getByRole("heading", { name: "Required flows" }),
    ).toBeInTheDocument();
    expect(screen.queryByLabelText("required flows")).toBeNull();
  });

  describe("topology sections", () => {
    function topologyFixture() {
      const nodes: Node[] = [
        {
          id: "zone-1",
          type: "NetworkSegment",
          data: { name: "Zone 1", cidr: null },
          view_data: { x_pos: 0, y_pos: 0 },
        },
        {
          id: "host-1",
          type: "Host",
          data: { name: "host-1" },
          view_data: { x_pos: 0, y_pos: 0 },
        },
        {
          id: "service-1",
          type: "Service",
          data: { name: "db-1", port: 5432, protocol: "tcp" },
          view_data: { x_pos: 0, y_pos: 0 },
        },
      ];
      const graph: GraphContract = {
        ...baseProps.graph,
        nodes,
        edges: [],
      };
      const projection = projectionOf({
        segments: [segmentRecord("zone-1", ["host-1"], { service_count: 1 })],
        hosts: [hostRecord("host-1", "zone-1", ["service-1"])],
        services: [serviceRecord("service-1", "host-1")],
        flow_groups: [
          flowGroupRecord("host-1", "host-1", ["service-1"], ["flow-1"]),
        ],
      });
      return {
        graph,
        projection,
        host: nodes[1]!,
        service: nodes[2]!,
      };
    }

    it("toggles the pin of the selected entity", async () => {
      const { graph, projection, host } = topologyFixture();
      const onTogglePin = vi.fn();
      const { rerender } = render(SelectionInspector, {
        props: {
          ...baseProps,
          graph,
          selectable: host,
          projection,
          pinned: false,
          onTogglePin,
          onUpdate: vi.fn(),
        },
      });

      const pin = screen.getByRole("button", { name: "Pin Host" });
      expect(pin).toHaveAttribute("aria-pressed", "false");
      await fireEvent.click(pin);
      expect(onTogglePin).toHaveBeenCalledWith("host-1");

      await rerender({
        ...baseProps,
        graph,
        selectable: host,
        projection,
        pinned: true,
        onTogglePin,
        onUpdate: vi.fn(),
      });

      expect(
        screen.getByRole("button", { name: "Unpin Host" }),
      ).toHaveAttribute("aria-pressed", "true");
    });

    it("hides the pin action when the document cannot pin", () => {
      const { graph, projection, host } = topologyFixture();
      render(SelectionInspector, {
        props: {
          ...baseProps,
          graph,
          selectable: host,
          projection,
          onUpdate: vi.fn(),
        },
      });

      expect(screen.queryByRole("button")).toBeNull();
      expect(screen.queryByText(/^Pin /)).toBeNull();
    });

    it("shows the relationship summary and draft reachability", () => {
      const { graph, projection, service } = topologyFixture();
      render(SelectionInspector, {
        props: {
          ...baseProps,
          graph,
          selectable: service,
          projection,
          projectionSource: "draft" as const,
          onUpdate: vi.fn(),
        },
      });

      expect(
        screen.getByRole("heading", { name: "Relationships" }),
      ).toBeInTheDocument();
      expect(screen.getByText("Runs on host-1")).toBeInTheDocument();
      expect(
        screen.getByText("Draft reachability · Save before simulation"),
      ).toBeInTheDocument();
    });

    it("hides draft reachability for a saved projection", () => {
      const { graph, projection, service } = topologyFixture();
      render(SelectionInspector, {
        props: {
          ...baseProps,
          graph,
          selectable: service,
          projection,
          onUpdate: vi.fn(),
        },
      });

      expect(
        screen.queryByText("Draft reachability · Save before simulation"),
      ).toBeNull();
    });

    it("reports a typed placement issue", () => {
      const graph: GraphContract = {
        ...baseProps.graph,
        nodes: [
          {
            id: "orphan-1",
            type: "Host",
            data: { name: "orphan-1" },
            view_data: { x_pos: 0, y_pos: 0 },
          },
        ],
      };
      render(SelectionInspector, {
        props: {
          ...baseProps,
          graph,
          selectable: graph.nodes[0]!,
          projection: projectionOf({
            issues: [issueRecord("host_without_segment", "orphan-1")],
          }),
          onUpdate: vi.fn(),
        },
      });

      const section = document.querySelector("[data-placement-status]")!;
      expect(section.getAttribute("data-placement-status")).toBe(
        "placement_issue",
      );
      expect(section.getAttribute("data-placement-reason")).toBe(
        "host_without_segment",
      );
      expect(screen.getByText("no segment")).toBeInTheDocument();
    });

    it("shows the pending and error projection status", async () => {
      const { graph, projection, host } = topologyFixture();
      const { rerender } = render(SelectionInspector, {
        props: {
          ...baseProps,
          graph,
          selectable: host,
          projection,
          projectionStatus: "pending" as const,
          onUpdate: vi.fn(),
        },
      });

      expect(
        document.querySelector("[data-projection-status='pending']"),
      ).not.toBeNull();

      await rerender({
        ...baseProps,
        graph,
        selectable: host,
        projection,
        projectionStatus: "error" as const,
        onUpdate: vi.fn(),
      });

      expect(
        document.querySelector("[data-projection-status='error']"),
      ).not.toBeNull();
    });

    it("offers required flows from the accepted projection membership", async () => {
      const { graph, projection } = topologyFixture();
      const selectable = {
        id: "capability-1",
        type: "MissionCapability",
        data: {
          name: "Order entry",
          description: null,
          impact_weight: 1,
          min_operational_support: 1,
          required_flows: [],
        },
        view_data: { x_pos: 0, y_pos: 0 },
      } satisfies Node;

      render(SelectionInspector, {
        props: {
          ...baseProps,
          graph,
          selectable,
          projection,
          canEditFlows: true,
          onUpdate: vi.fn(),
        },
      });

      await fireEvent.click(
        screen.getByRole("button", { name: "Change required flows" }),
      );

      expect(screen.getByText("Zone 1")).toBeInTheDocument();
      expect(screen.getByText("db-1:5432")).toBeInTheDocument();
    });

    it("reports unknown reachability without an accepted projection", () => {
      const selectable = {
        id: "capability-1",
        type: "MissionCapability",
        data: {
          name: "Order entry",
          description: null,
          impact_weight: 1,
          min_operational_support: 1,
          required_flows: [],
        },
        view_data: { x_pos: 0, y_pos: 0 },
      } satisfies Node;

      render(SelectionInspector, {
        props: {
          ...baseProps,
          selectable,
          canEditFlows: true,
          onUpdate: vi.fn(),
        },
      });

      expect(screen.getByRole("status")).toHaveTextContent(
        "Reachable flows are unknown without an accepted projection.",
      );
    });

    it("labels reachable flow options from a draft projection as unsaved", () => {
      const { graph, projection } = topologyFixture();
      const selectable = {
        id: "capability-1",
        type: "MissionCapability",
        data: {
          name: "Order entry",
          description: null,
          impact_weight: 1,
          min_operational_support: 1,
          required_flows: [],
        },
        view_data: { x_pos: 0, y_pos: 0 },
      } satisfies Node;

      render(SelectionInspector, {
        props: {
          ...baseProps,
          graph,
          selectable,
          projection,
          projectionSource: "draft" as const,
          canEditFlows: true,
          onUpdate: vi.fn(),
        },
      });

      expect(screen.getByRole("status")).toHaveTextContent(
        "Draft reachability · Save before simulation",
      );
    });

    it("hides the pin action for an edge selection", () => {
      const edge = {
        id: "edge-1",
        type: "Runs",
        from_id: "host-1",
        to_id: "service-1",
        data: {},
      } satisfies Edge;
      render(SelectionInspector, {
        props: {
          ...baseProps,
          selectable: edge,
          pinned: false,
          onTogglePin: vi.fn(),
          onUpdate: vi.fn(),
        },
      });

      // Pinning applies to nodes and segment headers only, never to edges.
      expect(screen.queryByText(/^(Pin|Unpin) /)).toBeNull();
      expect(screen.queryByRole("button")).toBeNull();
    });
  });
});
