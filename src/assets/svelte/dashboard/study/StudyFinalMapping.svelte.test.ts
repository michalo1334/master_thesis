import { describe, expect, it, vi } from "vitest";
import type { DashboardApi } from "../dashboard-api";
import { StudyFinalMapping } from "./StudyFinalMapping.svelte";

function run(id: string) {
  return {
    id,
    manifest_id: `manifest-${id}`,
    manifest_title: `Manifest ${id}`,
    graph_title: "Graph",
    completed_at: "2026-03-01T00:00:00Z",
    plan_count: 4,
    trial_count: 40,
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((value) => {
    resolve = value;
  });
  return { promise, resolve };
}

function api() {
  return {
    listStudyTierRuns: vi.fn(),
    preflightStudy: vi.fn().mockResolvedValue({ status: "ok", errors: [] }),
  };
}

describe("StudyFinalMapping", () => {
  it("preflights an empty mapping and keeps its missing-tier message specific", async () => {
    const client = api();
    client.listStudyTierRuns.mockResolvedValue({ runs: [run("final-run")] });
    client.preflightStudy.mockResolvedValue({
      status: "rejected",
      errors: [{ code: "no_tiers" }],
    });
    const mapping = new StudyFinalMapping("spec-1", ["small"], ["pilot-run"]);
    mapping.api = client as unknown as DashboardApi;

    await mapping.loadRuns();
    await vi.waitFor(() => expect(mapping.preflightStatus).toBe("rejected"));

    expect(client.preflightStudy).toHaveBeenCalledWith({
      specification_id: "spec-1",
      mode: "final",
      tier_runs: [],
    });
    expect(mapping.missingTiers).toEqual(["small"]);
    expect(mapping.visiblePreflightErrors).toEqual([]);
  });

  it("keeps partial-mapping messages specific and shows other server errors", async () => {
    const client = api();
    client.listStudyTierRuns.mockImplementation(
      async (payload: { tier: string }) => ({
        runs: [run(`final-${payload.tier}`)],
      }),
    );
    client.preflightStudy.mockImplementation(
      async (payload: { tier_runs: { tier: string; run_id: string }[] }) => ({
        status: "rejected",
        errors:
          payload.tier_runs.length === 0
            ? [{ code: "no_tiers" }]
            : [
                { code: "tier_declaration_mismatch" },
                { code: "run_incompatible" },
              ],
      }),
    );
    const mapping = new StudyFinalMapping(
      "spec-1",
      ["small", "large"],
      ["pilot-run"],
    );
    mapping.api = client as unknown as DashboardApi;

    await mapping.loadRuns();
    expect(mapping.selectRun("small", "final-small")).toBe(true);
    await vi.waitFor(() => expect(mapping.preflightStatus).toBe("rejected"));

    expect(mapping.missingTiers).toEqual(["large"]);
    expect(mapping.missingSelectionMessage("large")).toBe(
      "Select one completed run for this tier.",
    );
    expect(mapping.visiblePreflightErrors).toEqual([
      { code: "run_incompatible" },
    ]);
  });

  it("ignores a stale final-run load", async () => {
    const client = api();
    const first = deferred<{ runs: ReturnType<typeof run>[] }>();
    const second = deferred<{ runs: ReturnType<typeof run>[] }>();
    client.listStudyTierRuns.mockReturnValueOnce(first.promise);
    client.listStudyTierRuns.mockReturnValueOnce(second.promise);
    const mapping = new StudyFinalMapping("spec-1", ["small"], ["pilot-run"]);
    mapping.api = client as unknown as DashboardApi;

    void mapping.loadRuns();
    void mapping.loadRuns();
    second.resolve({ runs: [run("final-new")] });
    await vi.waitFor(() => expect(mapping.isLoading).toBe(false));
    first.resolve({ runs: [run("final-old")] });
    await Promise.resolve();

    expect(mapping.runsByTier.small?.map((candidate) => candidate.id)).toEqual([
      "final-new",
    ]);
  });

  it("excludes pilot run IDs from final choices and selections", () => {
    const mapping = new StudyFinalMapping("spec-1", ["small"], ["pilot-run"]);
    mapping.runsByTier = { small: [run("pilot-run"), run("final-run")] };

    expect(
      mapping.availableRuns("small").map((candidate) => candidate.id),
    ).toEqual(["final-run"]);
    expect(mapping.selectRun("small", "pilot-run")).toBe(false);
    expect(mapping.selections).toEqual({});
  });

  it("rejects duplicate final-run selections", () => {
    const mapping = new StudyFinalMapping(
      "spec-1",
      ["small", "large"],
      ["pilot-run"],
    );
    mapping.runsByTier = {
      small: [run("final-run")],
      large: [run("final-run")],
    };

    expect(mapping.selectRun("small", "final-run")).toBe(true);
    expect(mapping.selectRun("large", "final-run")).toBe(false);
    expect(mapping.selections).toEqual({ small: "final-run" });
  });

  it("uses Final mode and retains server preflight errors", async () => {
    const client = api();
    client.preflightStudy.mockResolvedValue({
      status: "rejected",
      errors: [{ code: "run_incompatible" }],
    });
    const mapping = new StudyFinalMapping("spec-1", ["small"], ["pilot-run"]);
    mapping.api = client as unknown as DashboardApi;
    mapping.runsByTier = { small: [run("final-run")] };

    expect(mapping.selectRun("small", "final-run")).toBe(true);
    await vi.waitFor(() => expect(mapping.preflightStatus).toBe("rejected"));

    expect(client.preflightStudy).toHaveBeenCalledWith({
      specification_id: "spec-1",
      mode: "final",
      tier_runs: [{ tier: "small", run_id: "final-run" }],
    });
    expect(mapping.preflightErrors).toEqual([{ code: "run_incompatible" }]);
  });

  it("locks an accepted mapping and keeps it for a retry", async () => {
    const client = api();
    const mapping = new StudyFinalMapping("spec-1", ["small"], ["pilot-run"]);
    mapping.api = client as unknown as DashboardApi;
    mapping.runsByTier = { small: [run("final-one"), run("final-two")] };

    mapping.selectRun("small", "final-one");
    await vi.waitFor(() => expect(mapping.preflightStatus).toBe("ok"));
    expect(mapping.missingTiers).toEqual([]);
    expect(mapping.canRun).toBe(true);
    mapping.lockSelections();

    expect(mapping.locked).toBe(true);
    expect(mapping.canRun).toBe(false);
    expect(mapping.selectRun("small", "final-two")).toBe(false);
    mapping.clearRun("small");
    expect(mapping.tierSelections()).toEqual([
      { tier: "small", run_id: "final-one" },
    ]);
  });
});
