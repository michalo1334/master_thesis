<script lang="ts">
  import type { GraphSummary } from "../contract";
  import type { AnalysisOption } from "../dashboard-api";
  import type { WorkspaceDocument } from "../workspace/WorkspaceDocument.svelte";
  import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
  import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
  import { resolveInspector } from "./inspector-registry";

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

  let request = $derived.by(() =>
    resolveInspector({
      document,
      api,
      summaries,
      analyses,
      analysesStatus,
      onLoadAnalyses,
      onGraphAnalysesChange,
      onReportAnalysisChange,
      onOpenParent,
    }),
  );
</script>

{#if request}
  {#if request.key !== undefined}
    {#key request.key}
      <request.Component {...request.props} />
    {/key}
  {:else}
    <request.Component {...request.props} />
  {/if}
{/if}
