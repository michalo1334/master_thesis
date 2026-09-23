import type { Edge, Node } from "../../contracts.generated/graph";
import type { GraphSummary } from "../../contracts.generated/dashboard/graph";
import type { Component, ComponentProps } from "svelte";
import type { DashboardApi } from "../dashboard-api";
import type { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { WorkspaceDocument } from "../workspace/WorkspaceDocument.svelte";
import GraphInspector from "./graph/GraphInspector.svelte";
import SelectionInspector from "./graph/SelectionInspector.svelte";
import ReportInspector from "./report/ReportInspector.svelte";

export interface InspectorContext {
  document: WorkspaceDocument | undefined;
  api: DashboardApi;
  summaries?: readonly GraphSummary[];
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

const graphSelectablePerspective: InspectorPerspective = {
  id: "graph-selectable",
  matches: (context) =>
    context.document?.kind === "graph" &&
    context.document.selection !== undefined,
  create: (context) => {
    const document = graphDocument(context);
    const selectable = document.selection;
    if (!selectable) throw new Error("selectable required");
    return makeRequest(
      "selectable",
      SelectionInspector,
      {
        selectable,
        graph: document.graph,
        api: context.api,
        revisionId: document.loadedRevisionId,
        canEditFlows: !!document.loadedRevisionId && !document.isDirty,
        errors: document.selectedValidationErrors,
        onUpdate: (next: Node | Edge) => document.updateSelection(next),
      },
      document.loadedRevisionId,
    );
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
      errors: document.graphValidationErrors,
      onTitleChange: (title: string) => document.setTitle(title),
      onOpenParent: graph.parent_revision_id
        ? () => context.onOpenParent?.(graph.parent_revision_id!)
        : undefined,
    });
  },
};

function reportRequest(
  kind: "simulation-report" | "optimization-report",
  document: SimulationReportDocument | OptimizationReportDocument,
  _context: InspectorContext,
): InspectorRequest {
  return makeRequest(kind, ReportInspector, {
    document,
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
