import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, waitFor } from "@testing-library/svelte";
import type { Live } from "live_svelte";
import DashboardHost from "../DashboardHost.svelte";
import { WorkspaceModel } from "./workspace/WorkspaceModel.svelte";
import { createWorkspaceEnvelope } from "../ui-kit/workspace/workspace-persistence";

vi.mock("live_svelte", () => ({ useLiveEvent: vi.fn() }));

afterEach(() => {
  cleanup();
  localStorage.clear();
});

describe("DashboardHost persistence", () => {
  it("loads the restored selected document at startup once", async () => {
    const workspace = new WorkspaceModel();
    const envelope = createWorkspaceEnvelope(
      {
        state: workspace.toPersistence()!.state,
        documents: [
          {
            kind: "simulation-report",
            ids: {
              experimentId: "experiment-1",
              graphId: "graph-1",
              graphRevisionId: "revision-1",
            },
            title: "Report for Topology",
          },
        ],
        selectedDocumentKey:
          "simulation-report:experimentId:experiment-1,graphId:graph-1,graphRevisionId:revision-1",
      },
      1,
    );
    localStorage.setItem("dashboard.workspace.v1", JSON.stringify(envelope));
    const pushEvent = vi.fn((event, _payload, onReply) => {
      if (event === "fetch_analyses") onReply?.({ analyses: [] }, 1);
      return 1;
    });
    const live = { pushEvent } as unknown as Live;

    render(DashboardHost, { props: { live } });

    await waitFor(() =>
      expect(
        pushEvent.mock.calls.filter(
          ([event]) => event === "fetch_simulation_report",
        ),
      ).toHaveLength(1),
    );
    expect(pushEvent).toHaveBeenCalledWith(
      "fetch_simulation_report",
      expect.objectContaining({
        experiment_id: "experiment-1",
      }),
    );
  });
});
