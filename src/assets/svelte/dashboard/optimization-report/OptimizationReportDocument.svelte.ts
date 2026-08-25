import type {
  OptimizationCompletedEvent,
  OptimizationReport,
  OptimizationStrategy,
  FetchOptimizationReportReply,
} from "../contract";
import type { DashboardApi } from "../dashboard-api";
import type { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import { AsyncReportDocument } from "../workspace/WorkspaceDocument.svelte";
import type { DashboardRecoveryContext } from "../workspace/recovery-context";
import {
  isPersistedDocumentOfKind,
  type PersistedWorkspaceDocument,
} from "../../ui-kit/workspace/workspace-persistence";
import {
  toOptimizationAnalysis,
  type OptimizationAnalysis,
} from "./to-analysis";

export class OptimizationReportDocument extends AsyncReportDocument<"optimization"> {
  readonly kind = "optimization-report" as const;
  readonly documentLabel = "Report";
  readonly reportKind = "optimization" as const;
  readonly icon = "shield" as const satisfies string;

  get reportId(): string | null {
    return this.optimizationId;
  }

  get reportApiKind(): "simulation_report" | "optimization_report" {
    return "optimization_report";
  }
  readonly id = crypto.randomUUID();
  graphId = $state("");
  graphRevisionId = $state("");
  correlationId = $state<string | null>(null);
  runId = $state<string | null>(null);

  optimizationId = $state<string | null>(null);
  strategy: OptimizationStrategy;
  budget: number;
  optimizedGraphRevisionId = $state<string | undefined>();
  reportData = $state.raw<OptimizationReport | undefined>();
  analysis = $state.raw<OptimizationAnalysis | undefined>();
  openOptimizedGraph = $state<(() => Promise<boolean>) | undefined>();
  graphDiff = $state.raw<GraphDiffDocument | undefined>();
  graphDiffStatus = $state<"" | "loading" | "error">("");
  private createGraphDiff = $state<
    (() => Promise<GraphDiffDocument | undefined>) | undefined
  >();

  constructor({
    graphId,
    graphRevisionId,
    graphTitle,
    correlationId = null,
    analysisId,
    analysisTitle,
    strategy,
    budget,
  }: {
    graphId: string;
    graphRevisionId: string;
    graphTitle: string;
    correlationId?: string | null;
    analysisId?: string;
    analysisTitle?: string;
    strategy: OptimizationStrategy;
    budget: number;
  }) {
    super();
    this.graphId = graphId;
    this.graphRevisionId = graphRevisionId;
    this.correlationId = correlationId;
    this.analysisId = analysisId;
    this.analysisTitle = analysisTitle;
    this.strategy = strategy;
    this.budget = budget;
    this.title = `Optimization report for ${graphTitle}`;
  }

  setRunId(runId: string): void {
    this.runId = runId;
  }

  static fromPersisted(
    data: unknown,
    _context: DashboardRecoveryContext,
  ): OptimizationReportDocument | undefined {
    if (!isOptimizationReportPersisted(data)) return undefined;
    const report = new OptimizationReportDocument({
      graphId: data.ids.graphId,
      graphRevisionId: data.ids.graphRevisionId,
      graphTitle: data.title,
      strategy: "cvss",
      budget: 0,
    });
    report.title = data.title;
    report.markReady(
      data.ids.optimizationId,
      data.ids.optimizedGraphRevisionId ?? "",
      async () => false,
    );
    report.setPersisted(data);
    return report;
  }

  toPersisted(): PersistedWorkspaceDocument | undefined {
    if (!this.optimizationId) return undefined;
    return {
      kind: "optimization-report",
      ids: {
        optimizationId: this.optimizationId,
        graphId: this.graphId,
        graphRevisionId: this.graphRevisionId,
        ...(this.optimizedGraphRevisionId
          ? { optimizedGraphRevisionId: this.optimizedGraphRevisionId }
          : {}),
      },
      title: this.title,
    };
  }

  recover(context: DashboardRecoveryContext): void {
    const persisted = this.persistedData as
      PersistedOptimizationReport | undefined;
    if (!persisted) return;
    if (persisted.ids.optimizedGraphRevisionId) {
      this.markReady(
        persisted.ids.optimizationId,
        persisted.ids.optimizedGraphRevisionId,
        () =>
          context.workspace.openOptimizationResult(
            context.api,
            persisted.ids.optimizedGraphRevisionId!,
          ),
        () =>
          context.workspace.loadOptimizationGraphDiff(
            context.api,
            this.graphRevisionId,
            persisted.ids.optimizedGraphRevisionId!,
          ),
      );
    } else {
      this.markReady(persisted.ids.optimizationId, "", async () => false);
    }
    this.load(context.api, this.id, persisted.ids.optimizationId);
  }

  complete(
    api: DashboardApi,
    payload: OptimizationCompletedEvent,
    openOptimizedGraph: () => Promise<boolean>,
    createGraphDiff?: () => Promise<GraphDiffDocument | undefined>,
  ): void {
    this.markReady(
      payload.optimization_id,
      payload.output_graph_revision_id,
      openOptimizedGraph,
      createGraphDiff,
    );
    this.load(api, this.id, payload.optimization_id);
  }

  markReady(
    optimizationId: string,
    optimizedGraphRevisionId: string,
    openOptimizedGraph: () => Promise<boolean>,
    createGraphDiff?: () => Promise<GraphDiffDocument | undefined>,
  ): void {
    this.optimizationId = optimizationId;
    this.optimizedGraphRevisionId = optimizedGraphRevisionId;
    this.openOptimizedGraph = openOptimizedGraph;
    this.graphDiff = undefined;
    this.graphDiffStatus = "";
    this.createGraphDiff = createGraphDiff;
    this.status = "ready";
    this.reportData = undefined;
    this.analysis = undefined;
    this.errorReason = "";
    this.progress = null;
  }

  setReportData(data: FetchOptimizationReportReply): void {
    if (data.optimization_id !== this.optimizationId) return;
    this.reportData = data.report;
    this.analysis = toOptimizationAnalysis(data.report);
    this.graphId = data.graph_id;
    this.graphRevisionId = data.graph_revision_id;
    this.title = `Optimization report for ${data.graph_title}`;
    this.status = "loaded";
  }

  load(api: DashboardApi, documentId: string, optimizationId: string): void {
    this.optimizationId = optimizationId;
    this.status = "loading";
    this.loadProgress = null;
    this.errorReason = "";
    api.requestOptimizationReport(documentId, optimizationId);
  }

  async loadGraphDiff(): Promise<boolean> {
    if (this.graphDiff) return true;
    if (!this.createGraphDiff || this.graphDiffStatus === "loading") {
      return false;
    }

    this.graphDiffStatus = "loading";
    try {
      const graphDiff = await this.createGraphDiff();
      if (!graphDiff) {
        this.graphDiffStatus = "error";
        return false;
      }

      this.graphDiff = graphDiff;
      this.graphDiffStatus = "";
      return true;
    } catch {
      this.graphDiffStatus = "error";
      return false;
    }
  }
}

type PersistedOptimizationReport = PersistedWorkspaceDocument & {
  ids: {
    optimizationId: string;
    graphId: string;
    graphRevisionId: string;
    optimizedGraphRevisionId?: string;
  };
};

function isOptimizationReportPersisted(
  value: unknown,
): value is PersistedOptimizationReport {
  return isPersistedDocumentOfKind<PersistedOptimizationReport["ids"]>(
    value,
    "optimization-report",
    ["optimizationId", "graphId", "graphRevisionId"],
  );
}
