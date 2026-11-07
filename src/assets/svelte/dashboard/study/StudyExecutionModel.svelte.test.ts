import { describe, it, expect, vi } from "vitest";
import type {
  ExecutionEvent,
  Progress,
  Status,
} from "../../contracts.generated/dashboard/study";
import { StudyExecutionModel } from "./StudyExecutionModel.svelte";
import { WorkspaceModel } from "../workspace/WorkspaceModel.svelte";
import { apiFixture, pilot, status } from "./test-fixtures";

async function watched() {
  const api = apiFixture((event, payload) =>
    event === "continue_study_execution"
      ? { status: "accepted", request_id: payload.request_id }
      : event === "fetch_study_status"
        ? { execution: status() }
        : {},
  );
  const model = new StudyExecutionModel("execution-1", "doc", api, status());
  await model.watch();
  const watch = api.studyRequest.mock.calls.find(
    ([event]) => event === "watch_study_execution",
  )![1].watch_id;
  const event = (
    sequence: number,
    state: Status["state"] = "collecting_pilot",
  ): ExecutionEvent => ({
    document_id: "doc",
    execution_id: "execution-1",
    watch_id: watch,
    sequence,
    status: status(state),
    progress: {
      execution_id: "execution-1",
      status: status(state),
      phase: "pilot_collection",
      tier: null,
      replica: 0,
      warm_up: false,
      counters: [{ completed: 1, total: 2, unit: "simulation_trials" }],
      activity: null,
    },
  });
  return { api, model, event };
}
describe("Study execution ownership", () => {
  it("acknowledges one pending continuation and correlates completion before another request", async () => {
    const { api, model } = await watched();
    await model.continue();
    const request = model.pendingRequestId!;
    expect(model.canContinue).toBe(false);
    await model.continue();
    expect(
      api.studyRequest.mock.calls.filter(
        ([event]) => event === "continue_study_execution",
      ),
    ).toHaveLength(1);
    model.finished({
      document_id: "doc",
      execution_id: "execution-1",
      request_id: "stale",
      status: status(),
    });
    expect(model.pendingRequestId).toBe(request);
    model.finished({
      document_id: "doc",
      execution_id: "execution-1",
      request_id: request,
      status: status(),
    });
    expect(model.pendingRequestId).toBeNull();
    expect(model.canContinue).toBe(true);
  });
  it("keeps a completion that arrives before the acknowledgement cleared", async () => {
    let release!: (value: any) => void;
    const api = apiFixture((event) =>
      event === "continue_study_execution"
        ? new Promise((resolve) => (release = resolve))
        : { execution: status() },
    );
    const model = new StudyExecutionModel("execution-1", "doc", api, status());
    const command = model.continue();
    const request = model.pendingRequestId!;
    model.finished({
      document_id: "doc",
      execution_id: "execution-1",
      request_id: request,
      status: status(),
    });
    release({ status: "accepted", request_id: request });
    await command;
    expect(model.pendingRequestId).toBeNull();
  });
  it("rejects stale watch identities, duplicate presentation messages and other executions", async () => {
    const { model, event } = await watched();
    expect(model.observed(event(2), false)).toBe(true);
    expect(model.observed(event(1), false)).toBe(false);
    expect(model.observed(event(2), false)).toBe(false);
    expect(model.observed({ ...event(3), watch_id: "stale" }, false)).toBe(
      false,
    );
    expect(model.observed({ ...event(3), execution_id: "other" }, false)).toBe(
      false,
    );
    expect(model.progress?.counters[0].completed).toBe(1);
  });
  it("tracks attention per execution and preserves terminal accepted state against late events", async () => {
    const { model, event } = await watched();
    model.observed(event(2, "awaiting_final"), false);
    expect(model.attention).toBe(true);
    model.observed(event(3, "awaiting_final"), true);
    expect(model.attention).toBe(false);
    model.observed(event(4, "failed"), false);
    expect(model.attention).toBe(true);
    model.observed(event(5, "collecting_final"), false);
    expect(model.status?.state).toBe("failed");
  });
  it("reconnect reads current facts and clears transient requests without automatic progression", async () => {
    const { api, model } = await watched();
    await model.continue();
    api.studyRequest.mockClear();
    model.reconnect();
    expect(model.pendingRequestId).toBeNull();
    await vi.waitFor(() =>
      expect(api.studyRequest).toHaveBeenCalledWith("fetch_study_status", {
        execution_id: "execution-1",
      }),
    );
    expect(
      api.studyRequest.mock.calls.some(
        ([event]) =>
          event === "continue_study_execution" ||
          event === "start_study_execution",
      ),
    ).toBe(false);
  });
  it("keeps continuation state across selected executions and workspace tabs", async () => {
    const api = apiFixture((event, payload) =>
      event === "fetch_study_status"
        ? { execution: status() }
        : event === "continue_study_execution"
          ? { status: "accepted", request_id: payload.request_id }
          : {},
    );
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.openStudy({ study_id: "a", revision: 1 });
    document.selectExecution("execution-1");
    await vi.waitFor(() =>
      expect(document.selectedExecution?.status).not.toBeNull(),
    );
    await document.selectedExecution!.continue();
    const pending = document.selectedExecution!.pendingRequestId;
    workspace.openRuns();
    expect(document.selectedExecution!.pendingRequestId).toBe(pending);
    document.selectExecution("execution-2");
    expect(
      document.executionModels.find((m) => m.executionId === "execution-1")!
        .pendingRequestId,
    ).toBe(pending);
  });
  it.each(["recommended", "insufficient"] as const)(
    "uses only the accepted %s approval path",
    async (outcome) => {
      const calls: any[] = [];
      const api = apiFixture((event, payload) => {
        calls.push([event, payload]);
        return event === "approve_study_final"
          ? { execution: status("collecting_final") }
          : event === "fetch_study_status"
            ? { execution: status("collecting_final") }
            : {};
      });
      const model = new StudyExecutionModel(
        "execution-1",
        "doc",
        api,
        status("awaiting_final"),
      );
      model.pilot = pilot(outcome);
      if (outcome === "insufficient") {
        await model.approve();
        expect(calls).toHaveLength(0);
        model.candidateId = "tiny";
        model.overrideConfirmed = false;
        await model.approve();
        expect(calls).toHaveLength(0);
        model.overrideConfirmed = true;
      }
      await model.approve();
      expect(calls[0]).toEqual([
        "approve_study_final",
        {
          execution_id: "execution-1",
          approval:
            outcome === "recommended" ? "recommended" : "override_insufficient",
          candidate_id: outcome === "recommended" ? undefined : "tiny",
        },
      ]);
    },
  );
  it("sends a confirmed override candidate to the backend for validation", async () => {
    const error = {
      category: "validation_failed",
      issues: [
        {
          code: "invalid_approval",
          path: ["candidate_id"],
          message: "Choose a declared candidate.",
        },
      ],
    };
    const api = apiFixture((event) =>
      event === "approve_study_final"
        ? { status: "error", error }
        : event === "fetch_study_status"
          ? { execution: status("awaiting_final") }
          : {},
    );
    const model = new StudyExecutionModel(
      "execution-1",
      "doc",
      api,
      status("awaiting_final"),
    );
    model.pilot = pilot();
    model.candidateId = "unknown";
    model.overrideConfirmed = true;
    await model.approve();
    expect(api.studyRequest).toHaveBeenCalledWith("approve_study_final", {
      execution_id: "execution-1",
      approval: "override_insufficient",
      candidate_id: "unknown",
    });
    expect(model.error).toEqual(error);
    expect(model.status?.state).toBe("awaiting_final");
  });
  it("keeps newer same-state watch progress when an older refresh resolves later", async () => {
    let release!: (value: any) => void;
    const api = apiFixture((event) =>
      event === "fetch_study_status"
        ? new Promise((resolve) => (release = resolve))
        : {},
    );
    const model = new StudyExecutionModel(
      "execution-1",
      "doc",
      api,
      status("collecting_final"),
    );
    await model.watch();
    const watch = api.studyRequest.mock.calls.find(
      ([name]) => name === "watch_study_execution",
    )![1].watch_id;
    const snapshot = (tier: Progress["tier"], replica: number): Progress => ({
      execution_id: "execution-1",
      status: status("collecting_final"),
      phase: "final_collection",
      tier,
      replica,
      warm_up: false,
      counters: [{ completed: 1, total: 2, unit: "optimization_items" }],
      activity: null,
    });
    const refreshing = model.refresh();
    model.observed(
      {
        document_id: "doc",
        execution_id: "execution-1",
        watch_id: watch,
        sequence: 10,
        status: status("collecting_final"),
        progress: snapshot("medium", 0),
      },
      false,
    );
    release({
      execution: status("collecting_final"),
      progress: snapshot("small", 4),
    });
    await refreshing;
    expect(model.progress?.tier).toBe("medium");
    expect(model.progress?.replica).toBe(0);
  });

  it("rejects older status reads that finish after a newer status read", async () => {
    const releases: ((value: any) => void)[] = [];
    const api = apiFixture((event) =>
      event === "fetch_study_status"
        ? new Promise((resolve) => releases.push(resolve))
        : {},
    );
    const model = new StudyExecutionModel(
      "execution-1",
      "doc",
      api,
      status("collecting_final"),
    );
    const snapshot = (tier: Progress["tier"], replica: number): Progress => ({
      execution_id: "execution-1",
      status: status("collecting_final"),
      phase: "final_collection",
      tier,
      replica,
      warm_up: false,
      counters: [],
      activity: null,
    });
    const older = model.refresh(),
      newer = model.refresh();
    releases[1]({
      execution: status("collecting_final"),
      progress: snapshot("medium", 2),
    });
    await newer;
    releases[0]({
      execution: status("collecting_final"),
      progress: snapshot("small", 4),
    });
    await older;
    expect(model.progress?.tier).toBe("medium");
    expect(model.progress?.replica).toBe(2);
  });

  it("rejects a mismatched status reply and releases terminal observers", async () => {
    const { api, model, event } = await watched();
    const foreign = {
      ...event(2),
      status: { ...status("failed"), execution_id: "other" },
    };
    expect(model.observed(foreign, false)).toBe(false);
    expect(model.status?.state).toBe("collecting_pilot");
    expect(model.observed(event(3, "cancelled"), false)).toBe(true);
    expect(model.canContinue).toBe(false);
    expect(model.canCancel).toBe(false);
    expect(model.notice).toContain("cancelled");
    expect(api.studyRequest).toHaveBeenCalledWith("unwatch_study_execution", {
      document_id: "doc",
      watch_id: expect.any(String),
    });
    const terminalApi = apiFixture(() => ({ execution: status("cancelled") }));
    const terminal = new StudyExecutionModel("execution-1", "doc", terminalApi);
    await terminal.refresh();
    expect(
      terminalApi.studyRequest.mock.calls.some(
        ([name]) => name === "watch_study_execution",
      ),
    ).toBe(false);
  });
});
