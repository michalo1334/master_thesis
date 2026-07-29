<script lang="ts">
  import type { Live } from "live_svelte";
  import { untrack } from "svelte";
  import { useLiveEvent, useEventReply } from "live_svelte";
  import { DashboardModel } from "./dashboard/DashboardModel.svelte";
  import { createDashboardApi } from "./dashboard/dashboard-api";
  import type { LiveServer } from "./dashboard/dashboard-api";
  import Dashboard from "./Dashboard.svelte";
  import type {
    GraphSummary,
    FetchExperimentsPayload,
    FetchExperimentsReply,
    OptimizationCompletedEvent,
    OptimizationFailedEvent,
    SimulationCompletedEvent,
    SimulationFailedEvent,
    SimulationProgressEvent,
    FetchSimulationReportReply,
  } from "./dashboard/contract";
  import type { SimulationReportErrorEvent } from "./dashboard/contract";

  interface Props {
    live: Live;
    graphSummaries?: GraphSummary[];
  }

  const { live, graphSummaries = [] }: Props = $props();

  const fetchExperiments = useEventReply<
    FetchExperimentsReply,
    FetchExperimentsPayload
  >("fetch_experiments");

  const model = untrack(
    () =>
      new DashboardModel(
        createDashboardApi(live as LiveServer, fetchExperiments.execute),
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
    void model.onOptimizationCompleted(payload as OptimizationCompletedEvent);
  });

  useLiveEvent("optimization_failed", (payload: unknown) => {
    model.onOptimizationFailed(payload as OptimizationFailedEvent);
  });

  useLiveEvent("simulation_report_ready", (payload: unknown) => {
    model.onSimulationReportReady(payload as FetchSimulationReportReply);
  });

  useLiveEvent("simulation_report_error", (payload: unknown) => {
    model.onSimulationReportError(payload as SimulationReportErrorEvent);
  });
</script>

<Dashboard {model} />
