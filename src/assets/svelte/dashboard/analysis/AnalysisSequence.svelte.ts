import type {
  OptimizationCompletedEvent,
  OptimizationFailedEvent,
  OptimizationParams,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  SimulationParams,
} from "../contract";
import { formatDashboardErrorCode } from "../error-code";
import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";

export type AnalysisSequenceStage =
  | "idle"
  | "starting-baseline"
  | "awaiting-baseline"
  | "starting-optimization"
  | "awaiting-optimization"
  | "loading-output-graph"
  | "starting-after"
  | "awaiting-after"
  | "completed"
  | "failed";

export interface AnalysisJob {
  graphId: string;
  graphRevisionId: string;
  correlationId: string;
}

interface AnalysisSequenceOperations {
  startSimulation(
    document: EditableGraphDocument,
    params: SimulationParams,
    job: AnalysisJob,
  ): Promise<boolean>;
  startOptimization(
    document: EditableGraphDocument,
    params: OptimizationParams,
    job: AnalysisJob,
  ): Promise<boolean>;
  loadOutputGraph(
    graphRevisionId: string,
  ): Promise<EditableGraphDocument | undefined>;
}

type OperationEvent = {
  correlation_id: string;
  graph_id: string;
  graph_revision_id: string;
};

export class AnalysisSequence {
  stage = $state<AnalysisSequenceStage>("idle");
  progress = $state({ completed: 0, total: 3 });
  error = $state("");

  sourceGraphId = $state("");
  sourceGraphRevisionId = $state("");
  baselineSimulationCorrelationId = $state<string | null>(null);
  optimizationCorrelationId = $state<string | null>(null);
  outputGraphRevisionId = $state<string | null>(null);
  afterGraphId = $state<string | null>(null);
  afterGraphRevisionId = $state<string | null>(null);
  afterSimulationCorrelationId = $state<string | null>(null);

  private sourceDocument: EditableGraphDocument | undefined;
  private simulationParams: SimulationParams | undefined;
  private optimizationParams: OptimizationParams | undefined;

  constructor(private readonly operations: AnalysisSequenceOperations) {}

  get active(): boolean {
    return !["idle", "completed", "failed"].includes(this.stage);
  }

  get statusMessage(): string {
    if (this.stage === "failed") return this.error;
    if (this.stage === "completed") return "Compound analysis completed.";

    const labels: Partial<Record<AnalysisSequenceStage, string>> = {
      "starting-baseline": "Starting baseline simulation",
      "awaiting-baseline": "Baseline simulation running",
      "starting-optimization": "Starting optimization",
      "awaiting-optimization": "Optimization running",
      "loading-output-graph": "Loading optimized graph",
      "starting-after": "Starting after simulation",
      "awaiting-after": "After simulation running",
    };
    const label = labels[this.stage];
    return label
      ? `${label} (${this.progress.completed}/${this.progress.total}).`
      : "";
  }

  async start(
    document: EditableGraphDocument,
    simulationParams: SimulationParams,
    optimizationParams: OptimizationParams,
  ): Promise<boolean> {
    if (this.active || !document.loadedRevisionId) return false;

    this.reset(document, simulationParams, optimizationParams);
    this.stage = "starting-baseline";
    const sourceDocument = this.sourceDocument;
    if (!sourceDocument) {
      this.fail("Baseline simulation did not start.");
      return false;
    }

    const job = this.createJob(sourceDocument);
    if (!job) {
      this.fail("Baseline simulation did not start.");
      return false;
    }

    this.sourceGraphId = job.graphId;
    this.sourceGraphRevisionId = job.graphRevisionId;
    this.baselineSimulationCorrelationId = job.correlationId;
    this.stage = "awaiting-baseline";
    try {
      const started = await this.operations.startSimulation(
        sourceDocument,
        simulationParams,
        job,
      );
      if (!started && this.stage === "awaiting-baseline") {
        this.fail("Baseline simulation did not start.");
      }
      return started && !this.error;
    } catch {
      if (this.stage === "awaiting-baseline") {
        this.fail("Baseline simulation did not start.");
      }
      return false;
    }
  }

  onSimulationCompleted(payload: SimulationCompletedEvent): void {
    if (
      this.stage === "awaiting-baseline" &&
      this.matches(
        payload,
        this.baselineSimulationCorrelationId,
        this.sourceGraphId,
        this.sourceGraphRevisionId,
      )
    ) {
      this.progress.completed = 1;
      this.stage = "starting-optimization";
      void this.startOptimization();
      return;
    }

    if (
      this.stage === "awaiting-after" &&
      this.matches(
        payload,
        this.afterSimulationCorrelationId,
        this.afterGraphId,
        this.afterGraphRevisionId,
      )
    ) {
      this.progress.completed = 3;
      this.stage = "completed";
    }
  }

  onSimulationFailed(payload: SimulationFailedEvent): void {
    if (
      this.stage === "awaiting-baseline" &&
      this.matches(
        payload,
        this.baselineSimulationCorrelationId,
        this.sourceGraphId,
        this.sourceGraphRevisionId,
      )
    ) {
      this.fail(
        `Baseline simulation failed: ${formatDashboardErrorCode(payload.error.code)}`,
      );
      return;
    }

    if (
      this.stage === "awaiting-after" &&
      this.matches(
        payload,
        this.afterSimulationCorrelationId,
        this.afterGraphId,
        this.afterGraphRevisionId,
      )
    ) {
      this.fail(
        `After simulation failed: ${formatDashboardErrorCode(payload.error.code)}`,
      );
    }
  }

  onOptimizationCompleted(payload: OptimizationCompletedEvent): void {
    if (
      this.stage !== "awaiting-optimization" ||
      !this.matches(
        payload,
        this.optimizationCorrelationId,
        this.sourceGraphId,
        this.sourceGraphRevisionId,
      )
    ) {
      return;
    }

    this.progress.completed = 2;
    this.outputGraphRevisionId = payload.output_graph_revision_id;
    this.stage = "loading-output-graph";
    void this.startAfterSimulation();
  }

  onOptimizationFailed(payload: OptimizationFailedEvent): void {
    if (
      this.stage === "awaiting-optimization" &&
      this.matches(
        payload,
        this.optimizationCorrelationId,
        this.sourceGraphId,
        this.sourceGraphRevisionId,
      )
    ) {
      this.fail(
        `Optimization failed: ${formatDashboardErrorCode(payload.error.code)}`,
      );
    }
  }

  private async startOptimization(): Promise<void> {
    const { sourceDocument, optimizationParams } = this;
    if (!sourceDocument || !optimizationParams) {
      this.fail("Optimization did not start.");
      return;
    }

    try {
      if (this.stage !== "starting-optimization") return;
      const job = this.createJob(sourceDocument);
      if (!job) {
        this.fail("Optimization did not start.");
        return;
      }

      this.optimizationCorrelationId = job.correlationId;
      this.stage = "awaiting-optimization";
      const started = await this.operations.startOptimization(
        sourceDocument,
        optimizationParams,
        job,
      );
      if (!started && this.stage === "awaiting-optimization") {
        this.fail("Optimization did not start.");
      }
    } catch {
      if (this.stage === "awaiting-optimization") {
        this.fail("Optimization did not start.");
      }
    }
  }

  private async startAfterSimulation(): Promise<void> {
    const { outputGraphRevisionId, simulationParams } = this;
    if (!outputGraphRevisionId || !simulationParams) {
      this.fail("After simulation did not start.");
      return;
    }

    try {
      const document = await this.operations.loadOutputGraph(
        outputGraphRevisionId,
      );
      if (!document || this.stage !== "loading-output-graph") {
        this.fail("Could not load the optimized graph.");
        return;
      }

      this.stage = "starting-after";
      const job = this.createJob(document);
      if (!job) {
        this.fail("After simulation did not start.");
        return;
      }

      this.afterGraphId = job.graphId;
      this.afterGraphRevisionId = job.graphRevisionId;
      this.afterSimulationCorrelationId = job.correlationId;
      this.stage = "awaiting-after";
      const started = await this.operations.startSimulation(
        document,
        simulationParams,
        job,
      );
      if (!started && this.stage === "awaiting-after") {
        this.fail("After simulation did not start.");
      }
    } catch {
      if (["loading-output-graph", "awaiting-after"].includes(this.stage)) {
        this.fail("Could not load the optimized graph.");
      }
    }
  }

  private reset(
    document: EditableGraphDocument,
    simulationParams: SimulationParams,
    optimizationParams: OptimizationParams,
  ): void {
    const sourceDocument = new EditableGraphDocument();
    sourceDocument.replaceFromLoadedGraph($state.snapshot(document.graph));
    this.sourceDocument = sourceDocument;
    this.simulationParams = simulationParams;
    this.optimizationParams = optimizationParams;
    this.progress.completed = 0;
    this.progress.total = 3;
    this.error = "";
    this.sourceGraphId = sourceDocument.graph.id;
    this.sourceGraphRevisionId = sourceDocument.loadedRevisionId ?? "";
    this.baselineSimulationCorrelationId = null;
    this.optimizationCorrelationId = null;
    this.outputGraphRevisionId = null;
    this.afterGraphId = null;
    this.afterGraphRevisionId = null;
    this.afterSimulationCorrelationId = null;
  }

  private createJob(document: EditableGraphDocument): AnalysisJob | undefined {
    const graphRevisionId = document.loadedRevisionId;
    if (!graphRevisionId) return undefined;

    return {
      graphId: document.graph.id,
      graphRevisionId,
      correlationId: crypto.randomUUID(),
    };
  }

  private matches(
    payload: OperationEvent,
    correlationId: string | null,
    graphId: string | null,
    graphRevisionId: string | null,
  ): boolean {
    return (
      payload.correlation_id === correlationId &&
      payload.graph_id === graphId &&
      payload.graph_revision_id === graphRevisionId
    );
  }

  private fail(message: string): void {
    this.error = message;
    this.stage = "failed";
  }
}
