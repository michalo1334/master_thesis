import type {
  OptimizationCompletedEvent,
  OptimizationReport,
  OptimizationStrategy,
} from "../contract";
import {
  toOptimizationAnalysis,
  type OptimizationAnalysis,
} from "./to-analysis";

export class OptimizationReportDocument {
  readonly kind = "optimization-report" as const;
  readonly id = crypto.randomUUID();
  readonly graphId: string;
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
  optimizedGraphId = $state<string | undefined>();
  reportData = $state.raw<OptimizationReport | undefined>();
  analysis = $state.raw<OptimizationAnalysis | undefined>();
  openOptimizedGraph = $state<(() => Promise<boolean>) | undefined>();

  constructor({
    graphId,
    graphTitle,
    correlationId,
    strategy,
    budget,
  }: {
    graphId: string;
    graphTitle: string;
    correlationId: string;
    strategy: OptimizationStrategy;
    budget: number;
  }) {
    this.graphId = graphId;
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
  ): void {
    this.status = "completed";
    this.optimizedGraphId = payload.optimized_graph_id;
    this.reportData = payload.report;
    this.analysis = toOptimizationAnalysis(payload.report);
    this.openOptimizedGraph = openOptimizedGraph;
    this.errorReason = "";
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
