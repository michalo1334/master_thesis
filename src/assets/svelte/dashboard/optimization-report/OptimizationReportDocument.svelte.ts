import type {
  OptimizationCompletedEvent,
  OptimizationReport,
  OptimizationStrategy,
} from "../contract";
import type { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import type { IconName } from "../types";
import {
  toOptimizationAnalysis,
  type OptimizationAnalysis,
} from "./to-analysis";

export class OptimizationReportDocument {
  readonly kind = "optimization-report" as const;
  readonly icon = "shield" as const satisfies IconName;
  readonly id = crypto.randomUUID();
  readonly graphId: string;
  readonly graphRevisionId: string;
  readonly correlationId: string;

  title = $state("");
  status = $state<"pending" | "completed" | "error">("pending");
  hasUnread = $state(false);
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
    correlationId,
    strategy,
    budget,
  }: {
    graphId: string;
    graphRevisionId: string;
    graphTitle: string;
    correlationId: string;
    strategy: OptimizationStrategy;
    budget: number;
  }) {
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
    payload: OptimizationCompletedEvent,
    openOptimizedGraph: () => Promise<boolean>,
    createGraphDiff?: () => Promise<GraphDiffDocument | undefined>,
  ): void {
    this.status = "completed";
    this.optimizedGraphRevisionId = payload.graph_revision_id;
    this.reportData = payload.report;
    this.analysis = toOptimizationAnalysis(payload.report);
    this.openOptimizedGraph = openOptimizedGraph;
    this.graphDiff = undefined;
    this.graphDiffStatus = "";
    this.createGraphDiff = createGraphDiff;
    this.errorReason = "";
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

  markError(reason: string): void {
    this.status = "error";
    this.errorReason = reason;
  }

  markRead(): void {
    this.hasUnread = false;
  }

  markUnread(): void {
    this.hasUnread = true;
  }
}
