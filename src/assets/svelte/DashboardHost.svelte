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
    SimulationCompletedEvent,
    SimulationFailedEvent,
    SimulationProgressEvent,
    FetchSimulationReportReply,
    OptimizationCompletedEvent,
    OptimizationFailedEvent,
    OptimizationProgressEvent,
    SimulationReportErrorEvent,
  } from "./dashboard/contract";

  interface Props {
    live: Live;
    graphSummaries?: GraphSummary[];
  }

  const { live, graphSummaries = [] }: Props = $props();

  const model = untrack(
    () =>
      new DashboardModel(
        createDashboardApi(live as LiveServer),
        graphSummaries,
      ),
  );

  useLiveEvent("simulation_completed", (payload: unknown) => {
    model.onSimulationCompleted(payload as SimulationCompletedEvent);
  });

  useLiveEvent("simulation_failed", (payload: unknown) => {
    model.onSimulationFailed(payload as SimulationFailedEvent);
  });

  useLiveEvent("simulation_progress", (payload: unknown) => {
    model.onSimulationProgress(payload as SimulationProgressEvent);
  });

  useLiveEvent("optimization_completed", (payload: unknown) => {
    model.onOptimizationCompleted(payload as OptimizationCompletedEvent);
  });

  useLiveEvent("optimization_failed", (payload: unknown) => {
    model.onOptimizationFailed(payload as OptimizationFailedEvent);
  });

  useLiveEvent("optimization_progress", (payload: unknown) => {
    model.onOptimizationProgress(payload as OptimizationProgressEvent);
  });

  useLiveEvent("simulation_report_ready", (payload: unknown) => {
    model.onSimulationReportReady(payload as FetchSimulationReportReply);
  });

  useLiveEvent("simulation_report_error", (payload: unknown) => {
    model.onSimulationReportError(payload as SimulationReportErrorEvent);
  });
</script>

<Dashboard {model} />
