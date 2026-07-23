<script lang="ts">
  import type { Live } from "live_svelte";
  import { untrack } from "svelte";
  import { useLiveEvent, useEventReply } from "live_svelte";
  import { DashboardModel } from "./dashboard/DashboardModel.svelte";
  import { createDashboardApi } from "./dashboard/dashboard-api";
  import type { LiveServer } from "./dashboard/dashboard-api";
  import Dashboard from "./Dashboard.svelte";
  import type { GraphSummary } from "./dashboard/contract";
  import type {
    SimulationCompletedEvent,
    SimulationFailedEvent,
    FetchSimulationRunsPayload,
    FetchSimulationRunsReply,
  } from "./contracts.generated";

  interface Props {
    live: Live;
    graphSummaries?: GraphSummary[];
  }

  const { live, graphSummaries = [] }: Props = $props();

  const fetchSimRuns = useEventReply<
    FetchSimulationRunsReply,
    FetchSimulationRunsPayload
  >("fetch_simulation_runs");

  const model = untrack(
    () =>
      new DashboardModel(
        createDashboardApi(live as LiveServer, fetchSimRuns.execute),
        graphSummaries,
      ),
  );

  useLiveEvent("simulation_completed", (payload: unknown) => {
    model.onSimulationCompleted(payload as SimulationCompletedEvent);
  });

  useLiveEvent("simulation_failed", (payload: unknown) => {
    model.onSimulationFailed(payload as SimulationFailedEvent);
  });
</script>

<Dashboard {model} />
