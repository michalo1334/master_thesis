<script lang="ts">
  import type { ExecutionProgressEvent } from "./contracts.generated/dashboard";
  import type * as OptimizationContracts from "./contracts.generated/dashboard/optimization";
  import type * as SimulationContracts from "./contracts.generated/dashboard/simulation";
  import type {
    FolderSummary,
    GraphSummary,
  } from "./contracts.generated/dashboard/graph";
  import type {
    ExecutionEvent as StudyExecutionEvent,
    ContinueFinished as StudyContinueFinished,
  } from "./contracts.generated/dashboard/study";
  import type { RunCancelledEvent } from "./contracts.generated/dashboard/runs";

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
  interface Props {
    live: Live;
    graphSummaries?: GraphSummary[];
    folders?: FolderSummary[];
  }

  const { live, graphSummaries = [], folders = [] }: Props = $props();

  const model = untrack(
    () =>
      new DashboardModel(
        // LiveSvelte types still declare the legacy pushEvent return type.
        createDashboardApi(live as unknown as LiveServer),
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

  const persistence = $derived(model.workspace.toPersistence());
  $effect(() => {
    if (persistence)
      writeWorkspaceEnvelope("dashboard.workspace.v1", persistence);
  });

  useLiveEvent("simulation_completed", (payload: unknown) => {
    model.onSimulationCompleted(
      payload as SimulationContracts.SimulationCompletedEvent,
    );
  });

  useLiveEvent("simulation_failed", (payload: unknown) => {
    model.onSimulationFailed(
      payload as SimulationContracts.SimulationFailedEvent,
    );
  });

  useLiveEvent("simulation_progress", (payload: unknown) => {
    model.onProgress("simulation", payload as ExecutionProgressEvent);
  });

  useLiveEvent("optimization_completed", (payload: unknown) => {
    model.onOptimizationCompleted(
      payload as OptimizationContracts.OptimizationCompletedEvent,
    );
  });

  useLiveEvent("optimization_failed", (payload: unknown) => {
    model.onOptimizationFailed(
      payload as OptimizationContracts.OptimizationFailedEvent,
    );
  });

  useLiveEvent("optimization_progress", (payload: unknown) => {
    model.onProgress("optimization", payload as ExecutionProgressEvent);
  });

  useLiveEvent("simulation_report_ready", (payload: unknown) => {
    model.onReportReadyEvent({
      reportKind: "simulation",
      payload: payload as SimulationContracts.SimulationReportReadyEvent,
    });
  });

  useLiveEvent("simulation_report_progress", (payload: unknown) => {
    model.onReportProgress("simulation", payload as ExecutionProgressEvent);
  });

  useLiveEvent("simulation_report_error", (payload: unknown) => {
    model.onReportErrorEvent({
      reportKind: "simulation",
      payload: payload as SimulationContracts.SimulationReportErrorEvent,
    });
  });

  useLiveEvent("optimization_report_ready", (payload: unknown) => {
    model.onReportReadyEvent({
      reportKind: "optimization",
      payload: payload as OptimizationContracts.OptimizationReportReadyEvent,
    });
  });

  useLiveEvent("optimization_report_progress", (payload: unknown) => {
    model.onReportProgress("optimization", payload as ExecutionProgressEvent);
  });

  useLiveEvent("optimization_report_error", (payload: unknown) => {
    model.onReportErrorEvent({
      reportKind: "optimization",
      payload: payload as OptimizationContracts.OptimizationReportErrorEvent,
    });
  });

  useLiveEvent("study_progress", (payload: unknown) =>
    model.onStudyEvent(payload as StudyExecutionEvent),
  );
  useLiveEvent("study_continue_finished", (payload: unknown) =>
    model.onStudyContinueFinished(payload as StudyContinueFinished),
  );
  useLiveEvent("study_session_ready", () => model.reconcileStudies());

  useLiveEvent("run_cancelled", (payload: unknown) => {
    model.onRunCancelled(payload as RunCancelledEvent);
  });
</script>

<Dashboard {model} />
