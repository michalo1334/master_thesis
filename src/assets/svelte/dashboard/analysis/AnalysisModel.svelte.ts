import type { DashboardApi } from "../dashboard-api";
import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type {
  LoadedGraph,
  OptimizationCompletedEvent,
  OptimizationFailedEvent,
  OptimizationParams,
  OptimizationStrategy,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  SimulationParams,
} from "../contract";
import type { WorkspaceModel } from "../workspace/WorkspaceModel.svelte";
import { AnalysisSequence, type AnalysisJob } from "./AnalysisSequence.svelte";

export class AnalysisModel {
  open = $state(false);
  targetPickerOpen = $state(false);
  targetRevisionId = $state("");
  targetGraph = $state.raw<LoadedGraph>();
  includeSimulation = $state(false);
  includeOptimization = $state(false);
  selectedStrategies = $state<OptimizationStrategy[]>([]);
  isLoadingTarget = $state(false);
  private isSubmitting = $state(false);
  statusMessage = $state("");
  sequence: AnalysisSequence;

  constructor(
    readonly api: DashboardApi,
    readonly workspace: WorkspaceModel,
  ) {
    this.sequence = new AnalysisSequence({
      startSimulation: (document, params, job) =>
        this.startSequenceSimulation(document, params, job),
      startOptimization: (document, params, job) =>
        this.startSequenceOptimization(document, params, job),
      loadOutputGraph: (revisionId) => this.loadSequenceOutputGraph(revisionId),
    });
  }

  get isRunning(): boolean {
    return this.isSubmitting || this.sequence.active;
  }

  get targetFootholdHosts(): { id: string; name: string }[] {
    const graph = this.targetGraph;
    if (!graph) return [];

    return graph.nodes.flatMap((node) =>
      node.type === "Host" ? [{ id: node.id, name: node.data.name }] : [],
    );
  }

  get targetLabel(): string {
    const summary = this.workspace.graphSummaries.find(
      (graph) => graph.revision_id === this.targetRevisionId,
    );
    if (summary) {
      return `${summary.title} (${summary.revision_kind} #${summary.revision_number})`;
    }
    return this.targetGraph?.title ?? "Choose graph";
  }

  get runnableStrategies(): OptimizationStrategy[] {
    const hasFoothold = this.targetFootholdHosts.length > 0;
    return this.selectedStrategies.filter(
      (strategy) => strategy === "cvss" || hasFoothold,
    );
  }

  get needsSimulationSettings(): boolean {
    return this.runnableStrategies.some((strategy) =>
      [
        "simulation_informed",
        "topology_segmentation",
        "simulated_annealing",
      ].includes(strategy),
    );
  }

  get needsFoothold(): boolean {
    return this.runnableStrategies.some((strategy) => strategy !== "cvss");
  }

  get compoundValidationMessage(): string {
    if (!this.includeSimulation || !this.includeOptimization) return "";
    if (this.runnableStrategies.length === 0) {
      return "Select one runnable optimization strategy for the compound sequence.";
    }
    if (this.runnableStrategies.length > 1) {
      return "Select exactly one runnable optimization strategy for the compound sequence.";
    }
    return "";
  }

  get dialogStatusMessage(): string {
    return (
      this.compoundValidationMessage ||
      this.sequence.statusMessage ||
      this.statusMessage
    );
  }

  get canRun(): boolean {
    const compound = this.includeSimulation && this.includeOptimization;
    return (
      !this.isLoadingTarget &&
      !this.isRunning &&
      !!this.targetGraph &&
      (!this.includeSimulation || this.targetFootholdHosts.length > 0) &&
      (compound
        ? this.runnableStrategies.length === 1
        : this.includeSimulation ||
          (this.includeOptimization && this.runnableStrategies.length > 0))
    );
  }

  openDialog(): void {
    this.statusMessage = "";
    this.open = true;
    const active = this.workspace.activeGraph;
    if (active?.loadedRevisionId) {
      this.targetRevisionId = active.loadedRevisionId;
      this.targetGraph = active.graph;
      this.ensureFootholds();
    }
  }

  closeDialog(): void {
    if (this.isRunning) return;
    this.open = false;
    this.statusMessage = "";
  }

  openTargetPicker(): void {
    if (this.isRunning) return;
    this.statusMessage = "";
    this.open = false;
    this.targetPickerOpen = true;
  }

  setTargetPickerOpen(open: boolean): void {
    this.targetPickerOpen = open;
    if (!open) this.open = true;
  }

  async selectTarget(revisionId: string): Promise<boolean> {
    if (this.isLoadingTarget) return false;
    if (revisionId === this.targetRevisionId) return true;

    this.statusMessage = "";
    this.isLoadingTarget = true;
    try {
      const active = this.workspace.activeGraph;
      if (active?.loadedRevisionId === revisionId) {
        this.targetRevisionId = revisionId;
        this.targetGraph = active.graph;
      } else {
        const reply = await this.api.openGraph(revisionId);
        if (reply.status !== "ok" || !reply.graph) {
          this.statusMessage = "Unable to load the selected graph.";
          return false;
        }
        this.targetRevisionId = revisionId;
        this.targetGraph = reply.graph;
      }
      this.ensureFootholds();
      return true;
    } catch {
      this.statusMessage = "Unable to load the selected graph.";
      return false;
    } finally {
      this.isLoadingTarget = false;
    }
  }

  setStrategies(strategies: OptimizationStrategy[]): void {
    this.selectedStrategies = strategies;
  }

  async run(): Promise<boolean> {
    if (!this.canRun) return false;

    const target = await this.targetDocument();
    if (!target) return false;

    this.isSubmitting = true;
    this.statusMessage = "";
    try {
      if (target.isDirty && !(await target.saveIfDirty(this.api))) {
        this.statusMessage = target.saveStatusMessage;
        return false;
      }

      const simulationParams = $state.snapshot(this.workspace.simulationParams);
      const optimizationParams = $state.snapshot(
        this.workspace.optimizationParams,
      );
      if (this.includeSimulation && this.includeOptimization) {
        const [strategy] = this.runnableStrategies;
        if (!strategy) return false;

        const started = await this.sequence.start(target, simulationParams, {
          ...optimizationParams,
          strategy,
        });
        if (!started) {
          this.statusMessage =
            this.sequence.error || "Unable to start compound analysis.";
          return false;
        }

        this.open = false;
        return true;
      }

      const tasks: Promise<boolean>[] = [];
      if (this.includeSimulation) {
        tasks.push(this.runSimulation(target, simulationParams));
      }
      if (this.includeOptimization) {
        for (const strategy of this.runnableStrategies) {
          tasks.push(
            this.runOptimization(target, { ...optimizationParams, strategy }),
          );
        }
      }

      const started = (await Promise.all(tasks)).some(Boolean);
      if (!started) {
        this.statusMessage = "Unable to start analysis.";
        return false;
      }

      this.open = false;
      return true;
    } finally {
      this.isSubmitting = false;
    }
  }

  async runSimulation(
    document: EditableGraphDocument,
    params: SimulationParams,
    job: AnalysisJob | undefined = undefined,
  ): Promise<boolean> {
    if (this.sequence.active && !job) {
      this.workspace.statusMessage = "Compound analysis is in progress.";
      return false;
    }

    const expectedJob = job ?? this.createJob(document);
    if (!expectedJob) return false;
    const report = this.workspace.createPendingReport({
      graphId: expectedJob.graphId,
      graphRevisionId: expectedJob.graphRevisionId,
      correlationId: expectedJob.correlationId,
      graphTitle: document.title,
    });

    try {
      const result = await document.startSimulation(
        this.api,
        params,
        expectedJob.correlationId,
      );
      if (!result) {
        report.markError("Simulation failed.");
        this.workspace.markReportReadState(report);
        return false;
      }
      if (result.status === "rejected") {
        report.markError(result.reason || "Simulation rejected.");
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = result.reason
          ? `Simulation rejected: ${result.reason}`
          : "Simulation was rejected.";
        return false;
      }
      if (
        result.graphId !== expectedJob.graphId ||
        result.graphRevisionId !== expectedJob.graphRevisionId ||
        result.correlationId !== expectedJob.correlationId
      ) {
        report.markError("Simulation request returned unexpected identifiers.");
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = report.errorReason;
        return false;
      }
      return true;
    } catch {
      report.markError("Simulation failed.");
      this.workspace.markReportReadState(report);
      this.workspace.statusMessage = report.errorReason;
      return false;
    }
  }

  async runOptimization(
    document: EditableGraphDocument,
    params: OptimizationParams,
    job: AnalysisJob | undefined = undefined,
  ): Promise<boolean> {
    if (this.sequence.active && !job) {
      this.workspace.statusMessage = "Compound analysis is in progress.";
      return false;
    }
    const expectedJob = job ?? this.createJob(document);
    if (!expectedJob) return false;

    const optimizationParams = this.withSupportedObjective(params);
    const report = this.workspace.createPendingOptimizationReport({
      graphId: expectedJob.graphId,
      graphRevisionId: expectedJob.graphRevisionId,
      graphTitle: document.title,
      correlationId: expectedJob.correlationId,
      strategy: optimizationParams.strategy,
      budget: optimizationParams.budget,
    });

    try {
      const reply = await document.startOptimization(
        this.api,
        optimizationParams,
        expectedJob.correlationId,
      );
      if (!reply) {
        report.markError("Optimization failed.");
        this.workspace.markReportReadState(report);
        return false;
      }
      if (reply.status === "rejected") {
        report.markError(reply.reason || "Optimization rejected.");
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = report.errorReason;
        return false;
      }
      if (
        reply.graph_revision_id !== expectedJob.graphRevisionId ||
        reply.correlation_id !== expectedJob.correlationId
      ) {
        report.markError(
          "Optimization request returned unexpected identifiers.",
        );
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = report.errorReason;
        return false;
      }
      return true;
    } catch {
      report.markError("Optimization failed.");
      this.workspace.markReportReadState(report);
      this.workspace.statusMessage = report.errorReason;
      return false;
    }
  }

  onSimulationCompleted(payload: SimulationCompletedEvent): void {
    this.sequence.onSimulationCompleted(payload);
  }

  onSimulationFailed(payload: SimulationFailedEvent): void {
    this.sequence.onSimulationFailed(payload);
  }

  onOptimizationCompleted(payload: OptimizationCompletedEvent): void {
    this.sequence.onOptimizationCompleted(payload);
  }

  onOptimizationFailed(payload: OptimizationFailedEvent): void {
    this.sequence.onOptimizationFailed(payload);
  }

  private async targetDocument(): Promise<EditableGraphDocument | undefined> {
    const active = this.workspace.activeGraph;
    if (active?.loadedRevisionId === this.targetRevisionId) return active;
    if (!this.targetGraph) {
      this.statusMessage = "Select a graph to analyze.";
      return undefined;
    }

    const document = new EditableGraphDocument();
    document.replaceFromLoadedGraph(this.targetGraph);
    return document;
  }

  private async startSequenceSimulation(
    document: EditableGraphDocument,
    params: SimulationParams,
    job: AnalysisJob,
  ): Promise<boolean> {
    return this.runSimulation(document, params, job);
  }

  private async startSequenceOptimization(
    document: EditableGraphDocument,
    params: OptimizationParams,
    job: AnalysisJob,
  ): Promise<boolean> {
    return this.runOptimization(document, params, job);
  }

  private async loadSequenceOutputGraph(
    revisionId: string,
  ): Promise<EditableGraphDocument | undefined> {
    try {
      const reply = await this.api.openGraph(revisionId);
      if (
        reply.status !== "ok" ||
        !reply.graph ||
        reply.graph.revision_id !== revisionId
      ) {
        return undefined;
      }

      const document = new EditableGraphDocument();
      document.replaceFromLoadedGraph(reply.graph);
      return document;
    } catch {
      return undefined;
    }
  }

  private ensureFootholds(): void {
    const hosts = this.targetFootholdHosts;
    const hasSimulationFoothold = hosts.some(
      (host) =>
        host.id === this.workspace.simulationParams.initial_foothold_node_id,
    );
    if (!hasSimulationFoothold) {
      this.workspace.simulationParams.initial_foothold_node_id =
        hosts[0]?.id ?? "";
    }

    const hasOptimizationFoothold = hosts.some(
      (host) =>
        host.id ===
        this.workspace.optimizationParams.simulation_params
          .initial_foothold_node_id,
    );
    if (!hasOptimizationFoothold) {
      this.workspace.optimizationParams.simulation_params.initial_foothold_node_id =
        hosts[0]?.id ?? "";
    }

    if (hosts.length === 0) {
      this.selectedStrategies = this.selectedStrategies.filter(
        (strategy) => strategy === "cvss",
      );
    }
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

  private withSupportedObjective(
    params: OptimizationParams,
  ): OptimizationParams {
    const supportsMissionImpact =
      params.strategy === "simulation_informed" ||
      params.strategy === "simulated_annealing";
    return {
      ...params,
      objective: supportsMissionImpact ? params.objective : "blast_radius",
    };
  }
}
