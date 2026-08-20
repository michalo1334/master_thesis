<script lang="ts">
  import type { Live } from "live_svelte";
  import { untrack } from "svelte";
  import { useLiveEvent } from "live_svelte";
  import { DashboardModel } from "./dashboard/DashboardModel.svelte";
  import { createDashboardApi } from "./dashboard/dashboard-api";
  import type { LiveServer } from "./dashboard/dashboard-api";
  import Dashboard from "./Dashboard.svelte";
  import type {
    GraphSummary,
    FolderSummary,
    SimulationCompletedEvent,
    SimulationFailedEvent,
    ExecutionProgressEvent,
    SimulationReportReadyEvent,
    OptimizationCompletedEvent,
    OptimizationFailedEvent,
    SimulationReportErrorEvent,
    OptimizationReportReadyEvent,
    OptimizationReportErrorEvent,
    WorkflowCompletedEvent,
    WorkflowFailedEvent,
  } from "./dashboard/contract";

  interface Props {
    live: Live;
    graphSummaries?: GraphSummary[];
    folders?: FolderSummary[];
  }

  const { live, graphSummaries = [], folders = [] }: Props = $props();

  const model = untrack(
    () =>
      new DashboardModel(
        createDashboardApi(live as LiveServer),
        graphSummaries,
        folders,
      ),
  );
  void model.workspace.loadAnalyses(model.api);

  useLiveEvent("simulation_completed", (payload: unknown) => {
    model.onSimulationCompleted(payload as SimulationCompletedEvent);
  });

  useLiveEvent("simulation_failed", (payload: unknown) => {
    model.onSimulationFailed(payload as SimulationFailedEvent);
  });

  useLiveEvent("simulation_progress", (payload: unknown) => {
    model.onProgress("simulation", payload as ExecutionProgressEvent);
  });

  useLiveEvent("optimization_completed", (payload: unknown) => {
    model.onOptimizationCompleted(payload as OptimizationCompletedEvent);
  });

  useLiveEvent("optimization_failed", (payload: unknown) => {
    model.onOptimizationFailed(payload as OptimizationFailedEvent);
  });

  useLiveEvent("optimization_progress", (payload: unknown) => {
    model.onProgress("optimization", payload as ExecutionProgressEvent);
  });

  useLiveEvent("simulation_report_ready", (payload: unknown) => {
    model.onReportReadyEvent({
      reportKind: "simulation",
      payload: payload as SimulationReportReadyEvent,
    });
  });

  useLiveEvent("simulation_report_error", (payload: unknown) => {
    model.onReportErrorEvent({
      reportKind: "simulation",
      payload: payload as SimulationReportErrorEvent,
    });
  });

  useLiveEvent("optimization_report_ready", (payload: unknown) => {
    model.onReportReadyEvent({
      reportKind: "optimization",
      payload: payload as OptimizationReportReadyEvent,
    });
  });

  useLiveEvent("optimization_report_error", (payload: unknown) => {
    model.onReportErrorEvent({
      reportKind: "optimization",
      payload: payload as OptimizationReportErrorEvent,
    });
  });

  useLiveEvent("workflow_completed", (payload: unknown) => {
    model.onWorkflowCompleted(payload as WorkflowCompletedEvent);
  });

  useLiveEvent("workflow_failed", (payload: unknown) => {
    model.onWorkflowFailed(payload as WorkflowFailedEvent);
  });
</script>

<Dashboard {model} />
