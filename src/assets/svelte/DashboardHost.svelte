<script lang="ts">
  import type { Live } from "live_svelte";
  import { untrack } from "svelte";
  import { useLiveEvent } from "live_svelte";
  import { DashboardModel } from "./dashboard/DashboardModel.svelte";
  import { createDashboardApi } from "./dashboard/dashboard-api";
  import type { LiveServer } from "./dashboard/dashboard-api";
  import Dashboard from "./Dashboard.svelte";
  import {
    readWorkspaceEnvelope,
    writeWorkspaceEnvelope,
  } from "./ui-kit/workspace/workspace-persistence";
  import { isDashboardWorkspaceState } from "./dashboard/workspace/persisted-documents";
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
    EvaluationCompletedEvent,
    EvaluationFailedEvent,
    RunCancelledEvent,
    EvaluationReportReadyEvent,
    EvaluationReportErrorEvent,
  } from "./dashboard/contract";
  import type {
    EvaluationAnalysisReadyEvent,
    EvaluationAnalysisErrorEvent,
  } from "./contracts.generated";

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
  model.workspace.restorePersistence(
    readWorkspaceEnvelope("dashboard.workspace.v1", isDashboardWorkspaceState),
  );
  if (model.workspace.selectedDocumentId) {
    model.workspace.selectDocument(model.workspace.selectedDocumentId);
  }

  $effect(() => {
    const persistence = model.workspace.toPersistence();
    if (persistence) {
      untrack(() =>
        writeWorkspaceEnvelope("dashboard.workspace.v1", persistence),
      );
    }
  });

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

  useLiveEvent("simulation_report_progress", (payload: unknown) => {
    model.onReportProgress("simulation", payload as ExecutionProgressEvent);
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

  useLiveEvent("optimization_report_progress", (payload: unknown) => {
    model.onReportProgress("optimization", payload as ExecutionProgressEvent);
  });

  useLiveEvent("optimization_report_error", (payload: unknown) => {
    model.onReportErrorEvent({
      reportKind: "optimization",
      payload: payload as OptimizationReportErrorEvent,
    });
  });

  useLiveEvent("evaluation_completed", (payload: unknown) => {
    model.onEvaluationCompleted(payload as EvaluationCompletedEvent);
  });

  useLiveEvent("evaluation_failed", (payload: unknown) => {
    model.onEvaluationFailed(payload as EvaluationFailedEvent);
  });

  useLiveEvent("run_cancelled", (payload: unknown) => {
    model.onRunCancelled(payload as RunCancelledEvent);
  });

  useLiveEvent("evaluation_progress", (payload: unknown) => {
    model.onProgress("evaluation", payload as ExecutionProgressEvent);
  });

  useLiveEvent("evaluation_report_ready", (payload: unknown) => {
    model.onReportReadyEvent({
      reportKind: "evaluation",
      payload: payload as EvaluationReportReadyEvent,
    });
  });

  useLiveEvent("evaluation_report_progress", (payload: unknown) => {
    model.onReportProgress("evaluation", payload as ExecutionProgressEvent);
  });

  useLiveEvent("evaluation_report_error", (payload: unknown) => {
    model.onReportErrorEvent({
      reportKind: "evaluation",
      payload: payload as EvaluationReportErrorEvent,
    });
  });

  useLiveEvent("evaluation_analysis_ready", (payload: unknown) => {
    model.onEvaluationAnalysisReady(payload as EvaluationAnalysisReadyEvent);
  });

  useLiveEvent("evaluation_analysis_error", (payload: unknown) => {
    model.onEvaluationAnalysisError(payload as EvaluationAnalysisErrorEvent);
  });
</script>

<Dashboard {model} />
