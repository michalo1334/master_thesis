import type { DashboardApi } from "../dashboard-api";
import { formatDashboardErrorCode } from "../error-code";
import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type {
  LoadedGraph,
  OptimizationParams,
  OptimizationStrategy,
  SimulationParams,
  WorkflowCompletedEvent,
  WorkflowFailedEvent,
} from "../contract";
import type { WorkspaceModel } from "../workspace/WorkspaceModel.svelte";

interface WorkflowSnapshot {
  sourceGraphId: string;
  sourceGraphRevisionId: string;
  sourceGraphTitle: string;
  strategy: OptimizationStrategy;
  budget: number;
  analysisId: string;
  analysisTitle?: string;
}

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
  activeWorkflowId = $state<string | null>(null);
  private workflowSnapshots = new Map<string, WorkflowSnapshot>();
  statusMessage = $state("");

  constructor(
    readonly api: DashboardApi,
    readonly workspace: WorkspaceModel,
  ) {}

  get isRunning(): boolean {
    return this.isSubmitting || this.activeWorkflowId !== null;
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
      return "Select one runnable optimization strategy for the combined workflow.";
    }
    if (this.runnableStrategies.length > 1) {
      return "Select exactly one runnable optimization strategy for the combined workflow.";
    }
    return "";
  }

  get dialogStatusMessage(): string {
    return this.compoundValidationMessage || this.statusMessage;
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
        if (target.loadedRevisionId) {
          this.targetRevisionId = target.loadedRevisionId;
          this.targetGraph = $state.snapshot(target.graph);
        }
        const [strategy] = this.runnableStrategies;
        if (!strategy) return false;

        const workflowOptimizationParams = { ...optimizationParams, strategy };
        const started = await this.runWorkflow(
          target,
          simulationParams,
          workflowOptimizationParams,
        );
        if (!started) {
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
  ): Promise<boolean> {
    if (this.activeWorkflowId) {
      this.workspace.statusMessage = "Compound analysis is in progress.";
      return false;
    }

    const expectedJob = this.createJob(document);
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
        report.markErrorMessage("Simulation failed.");
        this.workspace.markReportReadState(report);
        return false;
      }
      if (result.status === "rejected") {
        if (result.error) {
          report.markError(result.error);
        } else {
          report.markErrorMessage("Simulation rejected.");
        }
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = result.error
          ? `Simulation rejected: ${formatDashboardErrorCode(result.error.code)}`
          : "Simulation was rejected.";
        return false;
      }
      if (
        result.graphId !== expectedJob.graphId ||
        result.graphRevisionId !== expectedJob.graphRevisionId ||
        result.correlationId !== expectedJob.correlationId
      ) {
        report.markErrorMessage(
          "Simulation request returned unexpected identifiers.",
        );
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = report.errorReason;
        return false;
      }
      return true;
    } catch {
      report.markErrorMessage("Simulation failed.");
      this.workspace.markReportReadState(report);
      this.workspace.statusMessage = report.errorReason;
      return false;
    }
  }

  async runOptimization(
    document: EditableGraphDocument,
    params: OptimizationParams,
  ): Promise<boolean> {
    if (this.activeWorkflowId) {
      this.workspace.statusMessage = "Compound analysis is in progress.";
      return false;
    }
    const expectedJob = this.createJob(document);
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
        report.markErrorMessage("Optimization failed.");
        this.workspace.markReportReadState(report);
        return false;
      }
      if (reply.status === "rejected") {
        if (reply.error) {
          report.markError(reply.error);
        } else {
          report.markErrorMessage("Optimization rejected.");
        }
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = report.errorReason;
        return false;
      }
      if (
        reply.graph_revision_id !== expectedJob.graphRevisionId ||
        reply.correlation_id !== expectedJob.correlationId
      ) {
        report.markErrorMessage(
          "Optimization request returned unexpected identifiers.",
        );
        this.workspace.markReportReadState(report);
        this.workspace.statusMessage = report.errorReason;
        return false;
      }
      return true;
    } catch {
      report.markErrorMessage("Optimization failed.");
      this.workspace.markReportReadState(report);
      this.workspace.statusMessage = report.errorReason;
      return false;
    }
  }

  onWorkflowCompleted(payload: WorkflowCompletedEvent): void {
    if (payload.workflow_id !== this.activeWorkflowId) return;

    const workflow = this.workflowSnapshots.get(payload.workflow_id);
    this.activeWorkflowId = null;
    this.workflowSnapshots.delete(payload.workflow_id);
    if (!workflow) {
      this.statusMessage = "Workflow completed without its request snapshot.";
      return;
    }

    const baselineReport = this.workspace.createPendingReport({
      graphId: workflow.sourceGraphId,
      graphRevisionId: workflow.sourceGraphRevisionId,
      graphTitle: workflow.sourceGraphTitle,
      analysisId: workflow.analysisId,
      analysisTitle: workflow.analysisTitle,
    });
    baselineReport.complete(
      this.api,
      payload.baseline_experiment_id,
      workflow.sourceGraphRevisionId,
    );
    this.workspace.markReportReadState(baselineReport);

    const optimizationReport = this.workspace.createPendingOptimizationReport({
      graphId: workflow.sourceGraphId,
      graphRevisionId: workflow.sourceGraphRevisionId,
      graphTitle: workflow.sourceGraphTitle,
      strategy: workflow.strategy,
      budget: workflow.budget,
      analysisId: workflow.analysisId,
      analysisTitle: workflow.analysisTitle,
    });
    optimizationReport.complete(
      this.api,
      {
        correlation_id: "",
        graph_id: workflow.sourceGraphId,
        graph_revision_id: workflow.sourceGraphRevisionId,
        optimization_id: payload.optimization_id,
        output_graph_revision_id: payload.output_graph_revision_id,
      },
      () =>
        this.workspace.openOptimizationResult(
          this.api,
          payload.output_graph_revision_id,
        ),
      () =>
        this.workspace.loadOptimizationGraphDiff(
          this.api,
          workflow.sourceGraphRevisionId,
          payload.output_graph_revision_id,
        ),
    );
    this.workspace.markReportReadState(optimizationReport);

    const postOptimizationReport = this.workspace.createPendingReport({
      graphId: workflow.sourceGraphId,
      graphRevisionId: payload.output_graph_revision_id,
      graphTitle: workflow.sourceGraphTitle,
      analysisId: workflow.analysisId,
      analysisTitle: workflow.analysisTitle,
    });
    postOptimizationReport.complete(
      this.api,
      payload.after_experiment_id,
      payload.output_graph_revision_id,
    );
    this.workspace.markReportReadState(postOptimizationReport);
    this.workspace.openComparisonReport(
      baselineReport,
      optimizationReport,
      postOptimizationReport,
    );
    this.statusMessage = "Compound analysis completed.";
  }

  onWorkflowFailed(payload: WorkflowFailedEvent): void {
    if (payload.workflow_id !== this.activeWorkflowId) return;

    this.activeWorkflowId = null;
    this.workflowSnapshots.delete(payload.workflow_id);
    this.statusMessage = `Compound analysis failed: ${formatDashboardErrorCode(payload.error.code)}`;
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

  private async runWorkflow(
    document: EditableGraphDocument,
    simulationParams: SimulationParams,
    optimizationParams: OptimizationParams,
  ): Promise<boolean> {
    const graphRevisionId = document.loadedRevisionId;
    if (!graphRevisionId) return false;

    try {
      const reply = await this.api.runWorkflow(
        graphRevisionId,
        crypto.randomUUID(),
        simulationParams,
        optimizationParams,
      );
      if (reply.status === "rejected") {
        this.statusMessage = reply.error
          ? `Workflow rejected: ${formatDashboardErrorCode(reply.error.code)}`
          : "Workflow was rejected.";
        return false;
      }
      if (!reply.workflow_id) {
        this.statusMessage = "Workflow request returned no workflow ID.";
        return false;
      }

      this.activeWorkflowId = reply.workflow_id;
      const analysisTitle = reply.title;
      this.workflowSnapshots.set(reply.workflow_id, {
        sourceGraphId: document.graph.id,
        sourceGraphRevisionId: graphRevisionId,
        sourceGraphTitle: document.title,
        strategy: optimizationParams.strategy,
        budget: optimizationParams.budget,
        analysisId: reply.workflow_id,
        ...(analysisTitle ? { analysisTitle } : {}),
      });
      return true;
    } catch {
      this.statusMessage = "Workflow failed to start.";
      return false;
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

  private createJob(
    document: EditableGraphDocument,
  ):
    | { graphId: string; graphRevisionId: string; correlationId: string }
    | undefined {
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
