import type { DashboardApi } from "../dashboard-api";
import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type {
  LoadedGraph,
  OptimizationParams,
  OptimizationStrategy,
  SimulationParams,
} from "../contract";
import type { WorkspaceModel } from "../workspace/WorkspaceModel.svelte";

export class AnalysisModel {
  open = $state(false);
  targetPickerOpen = $state(false);
  targetRevisionId = $state("");
  targetGraph = $state.raw<LoadedGraph>();
  includeSimulation = $state(false);
  includeOptimization = $state(false);
  selectedStrategies = $state<OptimizationStrategy[]>([]);
  isLoadingTarget = $state(false);
  isRunning = $state(false);
  statusMessage = $state("");

  constructor(
    readonly api: DashboardApi,
    readonly workspace: WorkspaceModel,
  ) {}

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

  get canRun(): boolean {
    return (
      !this.isLoadingTarget &&
      !this.isRunning &&
      !!this.targetGraph &&
      (!this.includeSimulation || this.targetFootholdHosts.length > 0) &&
      (this.includeSimulation ||
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

    this.isRunning = true;
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
      this.isRunning = false;
    }
  }

  async runSimulation(
    document: EditableGraphDocument,
    params: SimulationParams,
  ): Promise<boolean> {
    try {
      const result = await document.startSimulation(this.api, params);
      if (!result) return false;
      if (result.status === "rejected") {
        this.workspace.statusMessage = result.reason
          ? `Simulation rejected: ${result.reason}`
          : "Simulation was rejected.";
        return false;
      }
      this.workspace.createPendingReport(result);
      return true;
    } catch {
      return false;
    }
  }

  async runOptimization(
    document: EditableGraphDocument,
    params: OptimizationParams,
  ): Promise<boolean> {
    if (!document.loadedRevisionId) return false;

    const correlationId = crypto.randomUUID();
    const report = this.workspace.createPendingOptimizationReport({
      graphId: document.graph.id,
      graphRevisionId: document.loadedRevisionId,
      graphTitle: document.title,
      correlationId,
      strategy: params.strategy,
      budget: params.budget,
    });

    try {
      const reply = await document.startOptimization(
        this.api,
        params,
        correlationId,
      );
      if (!reply) {
        report.markError("Optimization failed.");
        this.markOptimizationReportReadState(report);
        return false;
      }
      if (reply.status === "rejected") {
        report.markError(reply.reason || "Optimization rejected.");
        this.markOptimizationReportReadState(report);
        this.workspace.statusMessage = report.errorReason;
        return false;
      }
      return true;
    } catch {
      report.markError("Optimization failed.");
      this.markOptimizationReportReadState(report);
      this.workspace.statusMessage = report.errorReason;
      return false;
    }
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

  private markOptimizationReportReadState(
    report: import("../optimization-report/OptimizationReportDocument.svelte").OptimizationReportDocument,
  ): void {
    if (this.workspace.selectedDocumentId === report.id) report.markRead();
    else report.markUnread();
  }
}
