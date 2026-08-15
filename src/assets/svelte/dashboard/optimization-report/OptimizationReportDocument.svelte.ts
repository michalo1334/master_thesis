import type {
  OptimizationCompletedEvent,
  DashboardError,
  OptimizationReport,
  OptimizationStrategy,
  FetchOptimizationReportReply,
} from "../contract";
import type { DashboardApi } from "../dashboard-api";
import { formatDashboardErrorCode } from "../error-code";
import type { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import type { ClientReportEvent, EventResult } from "../report-events";
import type { IconName } from "../types";
import { AsyncReportDocument } from "../workspace/WorkspaceDocument.svelte";
import {
  toOptimizationAnalysis,
  type OptimizationAnalysis,
} from "./to-analysis";

export class OptimizationReportDocument extends AsyncReportDocument {
  readonly kind = "optimization-report" as const;
  readonly icon = "shield" as const satisfies IconName;
  readonly id = crypto.randomUUID();
  readonly graphId: string;
  readonly graphRevisionId: string;
  correlationId = $state<string | null>(null);

  title = $state("");
  status = $state<
    "pending" | "completed" | "ready" | "loading" | "loaded" | "error"
  >("pending");
  hasUnread = $state(false);
  optimizationId = $state<string | null>(null);
  strategy: OptimizationStrategy;
  budget: number;
  completedSteps = $state(0);
  totalSteps = $state(0);
  phase = $state("");
  errorReason = $state("");
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
    strategy,
    budget,
  }: {
    graphId: string;
    graphRevisionId: string;
    graphTitle: string;
    correlationId?: string | null;
    strategy: OptimizationStrategy;
    budget: number;
  }) {
    super();
    this.graphId = graphId;
    this.graphRevisionId = graphRevisionId;
    this.correlationId = correlationId;
    this.strategy = strategy;
    this.budget = budget;
    this.title = `Optimization report for ${graphTitle}`;
  }

  setProgress(
    completedSteps: number,
    totalSteps: number,
    phase?: string,
  ): void {
    if (this.status !== "pending") return;
    this.completedSteps = completedSteps;
    this.totalSteps = totalSteps;
    this.phase = phase ?? "";
  }

  complete(
    api: DashboardApi,
    payload: OptimizationCompletedEvent,
    openOptimizedGraph: () => Promise<boolean>,
    createGraphDiff?: () => Promise<GraphDiffDocument | undefined>,
  ): void {
    this.optimizationId = payload.optimization_id;
    this.optimizedGraphRevisionId = payload.output_graph_revision_id;
    this.openOptimizedGraph = openOptimizedGraph;
    this.graphDiff = undefined;
    this.graphDiffStatus = "";
    this.createGraphDiff = createGraphDiff;
    this.errorReason = "";
    this.status = "completed";
    this.load(api, this.id, payload.optimization_id, this.graphRevisionId);
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
  }

  setReportData(data: FetchOptimizationReportReply): void {
    if (data.optimization_id !== this.optimizationId) return;
    this.reportData = data.report;
    this.analysis = toOptimizationAnalysis(data.report);
    this.title = `Optimization report for ${data.graph_title}`;
    this.status = "loaded";
  }

  accept(event: ClientReportEvent): EventResult {
    return event.visitOptimization(this);
  }

  load(
    api: DashboardApi,
    documentId: string,
    optimizationId: string,
    graphRevisionId: string,
  ): void {
    this.optimizationId = optimizationId;
    this.status = "loading";
    this.errorReason = "";
    api.requestReport({
      type: "optimization",
      documentId,
      reportId: optimizationId,
      graphRevisionId,
    });
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

  markError(error: DashboardError): void {
    this.markErrorMessage(formatDashboardErrorCode(error.code));
  }

  markErrorMessage(message: string): void {
    this.status = "error";
    this.errorReason = message;
  }

  markRead(): void {
    this.hasUnread = false;
  }

  markUnread(): void {
    this.hasUnread = true;
  }
}
