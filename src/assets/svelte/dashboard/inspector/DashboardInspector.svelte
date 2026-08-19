<script lang="ts">
  import type { GraphSummary, LoadedGraph, Selectable } from "../contract";
  import type { AnalysisOption } from "../dashboard-api";
  import type { WorkspaceDocument } from "../workspace/WorkspaceDocument.svelte";
  import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
  import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
  import GraphInspector from "./graph/GraphInspector.svelte";
  import EditableSelectionInspector from "./graph/EditableSelectionInspector.svelte";
  import MissionCapabilityInspector from "./mission-capabilities/MissionCapabilityInspector.svelte";
  import ReportInspector from "./report/ReportInspector.svelte";
  import { inspectorRegistry } from "./inspector-registry";

  interface Props {
    document: WorkspaceDocument | undefined;
    api: import("../dashboard-api").DashboardApi;
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

  type InspectorSelection =
    | { kind: "selectable"; selectable: Selectable }
    | {
        kind: "graph";
        graph: LoadedGraph;
        parentTitle?: string;
        onTitleChange: (title: string) => void;
      }
    | undefined;

  let {
    document,
    api,
    summaries = [],
    analyses,
    analysesStatus,
    onLoadAnalyses,
    onGraphAnalysesChange,
    onReportAnalysisChange,
    onOpenParent = undefined,
  }: Props = $props();

  let selection = $derived.by((): InspectorSelection => {
    if (!document || document.kind !== "graph") return undefined;
    const selectable = document.selection;
    if (selectable) return { kind: "selectable", selectable };

    const parentTitle = document.graph.parent_revision_id
      ? summaries.find(
          ({ revision_id }) =>
            revision_id === document.graph.parent_revision_id,
        )?.title
      : undefined;
    return {
      kind: "graph",
      graph: document.graph,
      parentTitle,
      onTitleChange: (title) => document.setTitle(title),
    };
  });
</script>

{#if selection?.kind === "graph"}
  <GraphInspector
    graph={selection.graph}
    parentTitle={selection.parentTitle}
    onTitleChange={selection.onTitleChange}
    onOpenParent={selection.graph.parent_revision_id
      ? () => onOpenParent?.(selection.graph.parent_revision_id!)
      : undefined}
    analysisIds={summaries.find(
      ({ revision_id }) => revision_id === selection.graph.revision_id,
    )?.analysis_ids ?? []}
    {analyses}
    {analysesStatus}
    {onLoadAnalyses}
    onAnalysesChange={(analysisIds) =>
      selection.graph.revision_id
        ? onGraphAnalysesChange(selection.graph.revision_id, analysisIds)
        : Promise.resolve(false)}
  />
{:else if selection?.kind === "selectable" && document?.kind === "graph" && selection.selectable.type === "MissionCapability"}
  {#key document.loadedRevisionId}
    <MissionCapabilityInspector
      selectable={selection.selectable}
      graph={document.graph}
      revisionId={document.loadedRevisionId}
      canEditFlows={!!document.loadedRevisionId && !document.isDirty}
      {api}
      onUpdate={(selectable) => document.updateSelection(selectable)}
    />
  {/key}
{:else if selection?.kind === "selectable" && document?.kind === "graph"}
  {@const Inspector = inspectorRegistry.selectableInspectors.forSelectable(
    selection.selectable,
  )}
  <Inspector
    selectable={selection.selectable}
    onUpdate={(selectable: Selectable) => document.updateSelection(selectable)}
  />
{:else if document?.kind === "simulation-report" || document?.kind === "optimization-report"}
  <ReportInspector
    {document}
    {analyses}
    onAnalysisChange={(analysisId) =>
      onReportAnalysisChange(document, analysisId)}
  />
{/if}
