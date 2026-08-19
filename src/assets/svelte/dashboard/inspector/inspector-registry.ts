import type { Component, ComponentProps } from "svelte";
import type { AnalysisOption, DashboardApi } from "../dashboard-api";
import type { GraphSummary, Selectable } from "../contract";
import type { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import { inspectorFor as selectableInspectorFor } from "../graph/presentation/registry";
import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { WorkspaceDocument } from "../workspace/WorkspaceDocument.svelte";
import GraphInspector from "./graph/GraphInspector.svelte";
import MissionCapabilityInspector from "./mission-capabilities/MissionCapabilityInspector.svelte";
import ReportInspector from "./report/ReportInspector.svelte";

/**
 * App-side inspector registry.
 *
 * Ordered perspectives dispatch one resolved request. Selectable inspectors
 * reuse the presentation registry (nodeRegistry + edgeRegistry → inspectorFor)
 * except MissionCapability, which has its own perspective keyed by
 * selectable.type. Every perspective factory returns exactly the props its
 * component expects - no context bag reaches an inspector.
 */
export interface InspectorContext {
  document: WorkspaceDocument | undefined;
  api: DashboardApi;
  summaries?: readonly GraphSummary[];
  analyses: readonly AnalysisOption[];
  analysesStatus: string;
  onLoadAnalyses: () => Promise<boolean>;
  onGraphAnalysesChange: (
    revisionId: string,
    analysisIds: string[],
  ) => Promise<boolean>;
  onReportAnalysisChange: (
    report: SimulationReportDocument | OptimizationReportDocument,
    analysisId: string | null,
  ) => Promise<boolean>;
  onOpenParent?: (revisionId: string) => void;
}

export interface InspectorRequest {
  readonly id: string;
  readonly Component: Component<any>;
  readonly props: Record<string, unknown>;
  readonly key?: unknown;
}

export interface InspectorPerspective {
  readonly id: string;
  matches(context: InspectorContext): boolean;
  create(context: InspectorContext): InspectorRequest;
}

function makeRequest<C extends Component<any, any, any>>(
  id: string,
  Component: C,
  props: ComponentProps<C>,
  key?: unknown,
): InspectorRequest {
  return { id, Component, props, key } as InspectorRequest;
}

interface SelectablePerspective {
  readonly id: string;
  create(context: InspectorContext, selectable: Selectable): InspectorRequest;
}

function matchesDocumentKind(
  kind: WorkspaceDocument["kind"],
): (context: InspectorContext) => boolean {
  return (context) => context.document?.kind === kind;
}

function graphDocument(context: InspectorContext): EditableGraphDocument {
  if (context.document?.kind !== "graph")
    throw new Error("graph context required");
  return context.document;
}

const missionCapabilityPerspective: SelectablePerspective = {
  id: "selectable-mission-capability",
  create: (context, selectable) => {
    if (selectable.type !== "MissionCapability")
      throw new Error("MissionCapability selectable required");
    const document = graphDocument(context);
    return makeRequest(
      "selectable-mission-capability",
      MissionCapabilityInspector,
      {
        selectable,
        graph: document.graph,
        api: context.api,
        revisionId: document.loadedRevisionId,
        canEditFlows: !!document.loadedRevisionId && !document.isDirty,
        onUpdate: (next: Selectable) => document.updateSelection(next),
      },
      document.loadedRevisionId,
    );
  },
};

const defaultSelectablePerspective: SelectablePerspective = {
  id: "selectable",
  create: (context, selectable) =>
    makeRequest("selectable", selectableInspectorFor(selectable), {
      selectable,
      onUpdate: (next: Selectable) =>
        graphDocument(context).updateSelection(next),
    }),
};

const selectablePerspectives: Readonly<Record<string, SelectablePerspective>> =
  {
    MissionCapability: missionCapabilityPerspective,
  };

const graphSelectablePerspective: InspectorPerspective = {
  id: "graph-selectable",
  matches: (context) =>
    context.document?.kind === "graph" &&
    context.document.selection !== undefined,
  create: (context) => {
    const selectable = graphDocument(context).selection;
    if (!selectable) throw new Error("selectable required");
    const perspective =
      selectablePerspectives[selectable.type] ?? defaultSelectablePerspective;
    return perspective.create(context, selectable);
  },
};

const graphPerspective: InspectorPerspective = {
  id: "graph",
  matches: matchesDocumentKind("graph"),
  create: (context) => {
    const document = graphDocument(context);
    const summaries = context.summaries ?? [];
    const graph = document.graph;
    const parentTitle = graph.parent_revision_id
      ? summaries.find(
          ({ revision_id }) => revision_id === graph.parent_revision_id,
        )?.title
      : undefined;
    return makeRequest("graph", GraphInspector, {
      graph,
      parentTitle,
      onTitleChange: (title: string) => document.setTitle(title),
      onOpenParent: graph.parent_revision_id
        ? () => context.onOpenParent?.(graph.parent_revision_id!)
        : undefined,
      analysisIds:
        summaries.find(({ revision_id }) => revision_id === graph.revision_id)
          ?.analysis_ids ?? [],
      analyses: context.analyses,
      analysesStatus: context.analysesStatus,
      onLoadAnalyses: context.onLoadAnalyses,
      onAnalysesChange: (analysisIds: string[]) =>
        graph.revision_id
          ? context.onGraphAnalysesChange(graph.revision_id, analysisIds)
          : Promise.resolve(false),
    });
  },
};

function reportRequest(
  kind: "simulation-report" | "optimization-report",
  document: SimulationReportDocument | OptimizationReportDocument,
  context: InspectorContext,
): InspectorRequest {
  return makeRequest(kind, ReportInspector, {
    document,
    analyses: context.analyses,
    onAnalysisChange: (analysisId: string | null) =>
      context.onReportAnalysisChange(document, analysisId),
  });
}

function reportPerspective(
  kind: "simulation-report" | "optimization-report",
): InspectorPerspective {
  return {
    id: kind,
    matches: matchesDocumentKind(kind),
    create: (context) => {
      return reportRequest(
        kind,
        context.document as
          SimulationReportDocument | OptimizationReportDocument,
        context,
      );
    },
  };
}

export const inspectorPerspectives: readonly InspectorPerspective[] = [
  graphSelectablePerspective,
  graphPerspective,
  reportPerspective("simulation-report"),
  reportPerspective("optimization-report"),
];

export function resolveInspector(
  context: InspectorContext,
): InspectorRequest | undefined {
  for (const perspective of inspectorPerspectives) {
    if (perspective.matches(context)) return perspective.create(context);
  }
  return undefined;
}
