import type {
  Edge,
  GraphContract,
  Node,
} from "../../../contracts.generated/graph";
import type { DashboardApi } from "../../dashboard-api";
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import SelectionInspector from "./SelectionInspector.svelte";

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
const baseProps = { graph, api: {} as DashboardApi, canEditFlows: false };

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
});
