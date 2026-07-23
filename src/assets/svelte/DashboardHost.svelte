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
    SimulationCompletedEvent,
    SimulationFailedEvent,
  } from "./dashboard/contract";

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
</script>

<Dashboard {model} />
