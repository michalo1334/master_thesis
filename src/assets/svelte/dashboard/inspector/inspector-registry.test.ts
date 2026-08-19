import { describe, expect, it, vi } from "vitest";
import { DocumentCatalogDocument } from "../document-catalog/DocumentCatalogDocument.svelte";
import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { DashboardApi } from "../dashboard-api";
import type {
  LoadedGraph,
  MissionCapabilityNode,
  Selectable,
} from "../contract";
import {
  resolveInspector,
  type InspectorContext,
  type InspectorRequest,
} from "./inspector-registry";
import EmptyInspector from "./EmptyInspector.svelte";
import GraphInspector from "./graph/GraphInspector.svelte";
import MissionCapabilityInspector from "./mission-capabilities/MissionCapabilityInspector.svelte";
import ReportInspector from "./report/ReportInspector.svelte";

function makeGraph(overrides: Partial<LoadedGraph> = {}): LoadedGraph {
  return {
    id: "graph-1",
    title: "Topology",
    revision_id: "revision-1",
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    nodes: [],
    edges: [],
    ...overrides,
  };
}

function makeGraphDocument(
  graph: LoadedGraph = makeGraph(),
): EditableGraphDocument {
  const document = new EditableGraphDocument();
  document.replaceFromLoadedGraph(graph);
  return document;
}

function makeContext(
  overrides: Partial<InspectorContext> = {},
): InspectorContext {
  return {
    document: makeGraphDocument(),
    api: {} as DashboardApi,
    summaries: [],
    analyses: [{ id: "analysis-1", title: "Baseline" }],
    analysesStatus: "",
    onLoadAnalyses: vi.fn().mockResolvedValue(true),
    onGraphAnalysesChange: vi.fn().mockResolvedValue(true),
    onReportAnalysisChange: vi.fn().mockResolvedValue(true),
    ...overrides,
  };
}

const capabilityNode: MissionCapabilityNode = {
  id: "mc-1",
  type: "MissionCapability",
  view_data: { x_pos: 0, y_pos: 0 },
  data: {
    name: "Capability A",
    description: null,
    impact_weight: 5,
    min_operational_support: 1,
    required_flows: [],
  },
};

function propsOf(
  request: InspectorRequest | undefined,
): Record<string, unknown> {
  return request?.props ?? {};
}

describe("resolveInspector", () => {
  it("resolves the graph inspector for an unselected graph document", () => {
    const onOpenParent = vi.fn();
    const document = makeGraphDocument(
      makeGraph({ parent_revision_id: "revision-0" }),
    );
    const context = makeContext({
      document,
      summaries: [
        {
          analysis_ids: ["analysis-1"],
          edge_count: 0,
          folder_id: null,
          graph_id: "graph-1",
          is_favorite: false,
          node_count: 0,
          parent_revision_id: "revision-0",
          revision_id: "revision-1",
          revision_kind: "original",
          revision_number: 1,
          title: "Parent",
        },
      ],
      onOpenParent,
    });

    const request = resolveInspector(context);

    expect(request?.id).toBe("graph");
    expect(request?.Component).toBe(GraphInspector);
    const props = propsOf(request);
    expect(props.graph).toBe(document.graph);
    expect(props.analysisIds).toEqual(["analysis-1"]);
    expect(props.analyses).toBe(context.analyses);
    expect(typeof props.onTitleChange).toBe("function");
    const onOpenParentProp = props.onOpenParent as () => void;
    onOpenParentProp();
    expect(onOpenParent).toHaveBeenCalledWith("revision-0");
  });

  it("keeps a root graph without parent title and callbacks", () => {
    const request = resolveInspector(makeContext());

    const props = propsOf(request);
    expect(props.parentTitle).toBeUndefined();
    expect(props.onOpenParent).toBeUndefined();
  });

  it("gives a selected node priority over the graph inspector", () => {
    const node = {
      id: "host-1",
      type: "Host",
      view_data: { x_pos: 0, y_pos: 0 },
      data: { name: "Host A" },
    } as const;
    const document = makeGraphDocument(makeGraph({ nodes: [node] }));
    document.selectNode(node.id);

    const request = resolveInspector(makeContext({ document }));

    expect(request?.id).toBe("selectable");
    expect(request?.Component).not.toBe(GraphInspector);
    expect(propsOf(request).selectable).toEqual(node);
    expect(typeof propsOf(request).onUpdate).toBe("function");
  });

  it("resolves MissionCapability with its key and dedicated props", () => {
    const document = makeGraphDocument(makeGraph({ nodes: [capabilityNode] }));
    document.selectNode(capabilityNode.id);

    const request = resolveInspector(makeContext({ document }));

    expect(request?.id).toBe("selectable-mission-capability");
    expect(request?.Component).toBe(MissionCapabilityInspector);
    expect(request?.key).toBe(document.loadedRevisionId);
    const props = propsOf(request);
    expect(props.selectable).toEqual(capabilityNode);
    expect(props.graph).toBe(document.graph);
    expect(props.revisionId).toBe("revision-1");
    expect(props.canEditFlows).toBe(true);
    expect(typeof props.onUpdate).toBe("function");
  });

  it("remounts MissionCapability via its key when the revision changes", () => {
    const document = makeGraphDocument(makeGraph({ nodes: [capabilityNode] }));
    document.selectNode(capabilityNode.id);
    const first = resolveInspector(makeContext({ document }));

    document.replaceFromLoadedGraph(
      makeGraph({ nodes: [capabilityNode], revision_id: "revision-2" }),
    );
    document.selectNode(capabilityNode.id);
    const second = resolveInspector(makeContext({ document }));

    expect(first?.key).toBe("revision-1");
    expect(second?.key).toBe("revision-2");
    expect(first?.key).not.toBe(second?.key);
  });

  it("propagates selection updates for MissionCapability through onUpdate", () => {
    const document = makeGraphDocument(makeGraph({ nodes: [capabilityNode] }));
    document.selectNode(capabilityNode.id);

    const request = resolveInspector(makeContext({ document }));
    const onUpdate = propsOf(request).onUpdate as (next: Selectable) => void;
    onUpdate({
      ...capabilityNode,
      data: { ...capabilityNode.data, name: "Renamed" },
    });

    expect(document.graph.nodes[0]).toMatchObject({
      id: "mc-1",
      data: { name: "Renamed" },
    });
  });

  it("falls back to the selectable inspector for an unknown selectable type", () => {
    const unknown = {
      id: "unknown-1",
      type: "UnknownType",
      view_data: { x_pos: 0, y_pos: 0 },
      data: {},
    } as unknown as Selectable;
    const document = makeGraphDocument(
      makeGraph({ nodes: [unknown as LoadedGraph["nodes"][number]] }),
    );
    document.selectNode(unknown.id);

    const request = resolveInspector(makeContext({ document }));

    expect(request?.id).toBe("selectable");
    expect(request?.Component).toBe(EmptyInspector);
    expect(propsOf(request).selectable).toEqual(unknown);
    expect(typeof propsOf(request).onUpdate).toBe("function");
  });

  it("resolves both report kinds to ReportInspector with the same props shape", () => {
    const simulation = new SimulationReportDocument(
      "Topology",
      "graph-1",
      "revision-1",
    );
    const optimization = new OptimizationReportDocument({
      graphId: "graph-1",
      graphRevisionId: "revision-1",
      graphTitle: "Topology",
      strategy: "cvss",
      budget: 3,
    });
    const context = makeContext();

    const simRequest = resolveInspector({ ...context, document: simulation });
    const optRequest = resolveInspector({ ...context, document: optimization });

    expect(simRequest?.id).toBe("simulation-report");
    expect(optRequest?.id).toBe("optimization-report");
    expect(simRequest?.Component).toBe(ReportInspector);
    expect(optRequest?.Component).toBe(ReportInspector);
    expect(propsOf(simRequest).document).toBe(simulation);
    expect(propsOf(optRequest).document).toBe(optimization);
    expect(propsOf(simRequest).analyses).toBe(context.analyses);
    expect(propsOf(optRequest).analyses).toBe(context.analyses);
  });

  it("routes report analysis changes through onReportAnalysisChange", async () => {
    const simulation = new SimulationReportDocument(
      "Topology",
      "graph-1",
      "revision-1",
    );
    const onReportAnalysisChange = vi.fn().mockResolvedValue(true);
    const context = makeContext({
      document: simulation,
      onReportAnalysisChange,
    });

    const request = resolveInspector(context);
    const onAnalysisChange = propsOf(request).onAnalysisChange as (
      analysisId: string | null,
    ) => Promise<boolean>;

    await onAnalysisChange("analysis-2");

    expect(onReportAnalysisChange).toHaveBeenCalledWith(
      simulation,
      "analysis-2",
    );
  });

  it("returns undefined for no document and unsupported documents", () => {
    expect(
      resolveInspector(makeContext({ document: undefined })),
    ).toBeUndefined();
    expect(
      resolveInspector(
        makeContext({ document: new DocumentCatalogDocument() }),
      ),
    ).toBeUndefined();
  });
});
