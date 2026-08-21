import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/svelte";
import type { DashboardApi } from "../dashboard-api";
import Runs from "./Runs.svelte";
import { RunsDocument } from "./RunsDocument.svelte";

afterEach(cleanup);

function renderRuns(fetchRuns: DashboardApi["fetchRuns"]) {
  return render(Runs, {
    props: {
      document: new RunsDocument(),
      api: { fetchRuns } as DashboardApi,
    },
  });
}

describe("Runs", () => {
  it("fetches and displays active runs", async () => {
    const fetchRuns = vi.fn().mockResolvedValue({
      runs: [
        {
          id: "simulation-1",
          kind: "simulation",
          title: "Gateway simulation",
          completed: 4,
          total: 10,
          status: "running",
          started_at: "2026-01-01T12:00:00Z",
        },
      ],
    });

    renderRuns(fetchRuns);

    await waitFor(() =>
      expect(screen.getByText("Gateway simulation")).toBeInTheDocument(),
    );
    expect(fetchRuns).toHaveBeenCalledOnce();
    expect(screen.getByText("4 / 10")).toBeInTheDocument();
    expect(screen.getByText("running")).toBeInTheDocument();
  });

  it("shows an empty state", async () => {
    renderRuns(vi.fn().mockResolvedValue({ runs: [] }));

    expect(await screen.findByText("No active runs.")).toBeInTheDocument();
  });

  it("shows an error state", async () => {
    renderRuns(vi.fn().mockRejectedValue(new Error("offline")));

    expect(await screen.findByText("Could not load runs.")).toBeInTheDocument();
  });
});
