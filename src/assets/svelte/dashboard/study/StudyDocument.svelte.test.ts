import type {
  EvaluationAnalysis,
  StudyAnalysisErrorEvent,
  StudyAnalysisProgressEvent,
  StudyAnalysisReadyEvent,
  StartStudyAnalysisPayload,
} from "../../contracts.generated/dashboard/evaluation";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { DashboardApi } from "../dashboard-api";
import { StudyDocument } from "./StudyDocument.svelte";
import type { StudyLockedInputs, StudyMode } from "./study-types";

const ATTEMPT_ONE = "attempt-one";
const ATTEMPT_TWO = "attempt-two";

function locked(overrides: Partial<StudyLockedInputs> = {}): StudyLockedInputs {
  return {
    title: "Study one",
    study_id: "study-one",
    specification_id: "spec-1",
    specification_version: 1,
    tiers: [
      {
        tier: "small",
        run_id: "run-1",
        manifest_title: "Baseline manifest",
        graph_title: "Gateway",
        plan_count: 5,
        trial_count: 50,
      },
    ],
    ...overrides,
  };
}

function analysis(mode: "study-pilot" | "study-analyze"): EvaluationAnalysis {
  return {
    capability_results: [],
    feasibility_summary: [],
    metadata: {
      command_mode: mode,
      family_scope: "study",
      family_size: 1,
      ...(mode === "study-pilot"
        ? {
            recommended_plan_selection_seed_count: 4,
            recommended_attacks_per_plan: 10,
            insufficient_pilot: false,
          }
        : {}),
    },
    pilot_results: [],
    primary_results: [],
    secondary_results: [],
  };
}

/** Locks a running attempt the way an accepted start reply does. */
function start(
  document: StudyDocument,
  mode: StudyMode = "pilot",
  attemptId = ATTEMPT_ONE,
): void {
  document.markStarted(mode);
  document.attemptId = attemptId;
}

function readyEvent(
  document: StudyDocument,
  overrides: Partial<StudyAnalysisReadyEvent> = {},
): StudyAnalysisReadyEvent {
  return {
    document_id: document.id,
    mode: "pilot",
    attempt_id: document.attemptId ?? ATTEMPT_ONE,
    archive: btoa("pilot-archive"),
    pilot_eligible: true,
    analysis: analysis("study-pilot"),
    ...overrides,
  };
}

function progressEvent(
  document: StudyDocument,
  overrides: Partial<StudyAnalysisProgressEvent> = {},
): StudyAnalysisProgressEvent {
  return {
    document_id: document.id,
    mode: "pilot",
    attempt_id: document.attemptId ?? ATTEMPT_ONE,
    phase: "waiting_for_service",
    ...overrides,
  };
}

function errorEvent(
  document: StudyDocument,
  overrides: Partial<StudyAnalysisErrorEvent> = {},
): StudyAnalysisErrorEvent {
  return {
    document_id: document.id,
    mode: "pilot",
    attempt_id: document.attemptId ?? ATTEMPT_ONE,
    phase: "waiting_for_service",
    error: { code: "transport" },
    ...overrides,
  };
}

function startApi(reply: {
  status: "accepted" | "rejected" | "invalid_request";
  document_id?: string | null;
  mode?: "pilot" | "final" | null;
  attempt_id?: string | null;
  errors?: { code: string }[];
}) {
  return {
    startStudyAnalysis: vi.fn().mockResolvedValue({
      status: reply.status,
      document_id: reply.document_id ?? null,
      mode: reply.mode ?? null,
      attempt_id: reply.attempt_id ?? null,
      errors: reply.errors ?? [],
    }),
    closeStudyDocument: vi.fn().mockResolvedValue({ status: "closed" }),
  } as unknown as DashboardApi;
}

function base64Of(bytes: readonly number[]): string {
  return btoa(String.fromCharCode(...bytes));
}

const payloads = (api: DashboardApi): StartStudyAnalysisPayload[] =>
  vi.mocked(api.startStudyAnalysis).mock.calls.map(([payload]) => payload);

/** Marks the separate Final mapping complete and preflighted. */
function primeFinalMapping(
  document: StudyDocument,
  runId = "final-run",
  preflight: "ok" | "rejected" | "idle" = "ok",
): void {
  document.finalMapping.selections = { small: runId };
  document.finalMapping.preflightStatus = preflight;
}

describe("StudyDocument", () => {
  beforeEach(() => {
    Object.defineProperty(URL, "createObjectURL", {
      configurable: true,
      writable: true,
      value: vi.fn(() => "blob:study"),
    });
    Object.defineProperty(URL, "revokeObjectURL", {
      configurable: true,
      writable: true,
      value: vi.fn(),
    });
    vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("locks the specification identity and the exact tier mapping", () => {
    const document = new StudyDocument("doc-1", locked());

    expect(document.id).toBe("doc-1");
    expect(document.title).toBe("Study one");
    expect(document.tierCount).toBe(1);
    expect(document.matchesLocks(locked())).toBe(true);
    expect(
      document.matchesLocks(
        locked({
          tiers: [{ tier: "small", run_id: "run-2" }],
        }),
      ),
    ).toBe(false);
    expect(document.matchesLocks(locked({ specification_version: 2 }))).toBe(
      false,
    );
  });

  it("never persists its ephemeral session", () => {
    const document = new StudyDocument("doc-1", locked());

    expect(document.toPersisted()).toBeUndefined();
  });

  it("tracks the named phase and mode while running", () => {
    const document = new StudyDocument("doc-1", locked());

    start(document);
    expect(document.status).toBe("running");
    expect(document.mode).toBe("pilot");
    expect(document.phase).toBe("building_bundle");

    document.applyPhase("waiting_for_service");
    expect(document.phase).toBe("waiting_for_service");
  });

  it("stores an eligible pilot and enables final for the locked inputs", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);

    expect(document.onReady(readyEvent(document))).toBe(true);

    expect(document.status).toBe("ready");
    expect(document.phase).toBe("complete");
    expect(document.pilotEligible).toBe(true);
    expect(document.canRunFinal).toBe(false);

    primeFinalMapping(document);
    expect(document.canRunFinal).toBe(true);
    expect(document.canRerunPilot).toBe(false);
  });

  it("keeps final disabled after an insufficient pilot and allows an identical rerun", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);

    document.onReady(readyEvent(document, { pilot_eligible: false }));

    expect(document.pilotBlocked).toBe(true);
    expect(document.canRunFinal).toBe(false);
    expect(document.canRerunPilot).toBe(true);
  });

  it("stores the final result and closes the final gate", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onReady(readyEvent(document));

    start(document, "final");
    document.onReady(
      readyEvent(document, {
        mode: "final",
        archive: btoa("final-archive"),
        analysis: analysis("study-analyze"),
        pilot_eligible: null,
      }),
    );

    expect(document.finalResult?.archive).toBe(btoa("final-archive"));
    expect(document.pilotEligible).toBe(true);
    expect(document.canRunFinal).toBe(false);
    expect(document.activeResultTab).toBe("final");
  });

  it("ignores events for another document, another mode, another attempt, or a settled attempt", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);

    expect(
      document.onProgress(progressEvent(document, { document_id: "doc-2" })),
    ).toBe(false);
    expect(
      document.onProgress(progressEvent(document, { mode: "final" })),
    ).toBe(false);
    expect(
      document.onProgress(progressEvent(document, { attempt_id: ATTEMPT_TWO })),
    ).toBe(false);
    expect(
      document.onReady(readyEvent(document, { document_id: "doc-2" })),
    ).toBe(false);
    expect(document.onError(errorEvent(document, { mode: "final" }))).toBe(
      false,
    );
    expect(document.phase).toBe("building_bundle");
    expect(document.status).toBe("running");

    document.onReady(readyEvent(document));
    expect(document.onReady(readyEvent(document))).toBe(false);
    expect(document.onProgress(progressEvent(document))).toBe(false);
  });

  it("rejects a delayed success from a superseded pilot attempt", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document, "pilot", ATTEMPT_ONE);
    document.onError(errorEvent(document, { attempt_id: ATTEMPT_ONE }));
    expect(document.canRetry).toBe(true);

    start(document, "pilot", ATTEMPT_TWO);

    expect(
      document.onReady(readyEvent(document, { attempt_id: ATTEMPT_ONE })),
    ).toBe(false);
    expect(document.pilotEligible).toBe(false);
    expect(document.canRunFinal).toBe(false);
    expect(document.status).toBe("running");

    expect(
      document.onReady(readyEvent(document, { attempt_id: ATTEMPT_TWO })),
    ).toBe(true);
    primeFinalMapping(document);
    expect(document.canRunFinal).toBe(true);
  });

  it("rejects a delayed failure from a superseded final attempt", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onReady(readyEvent(document));

    start(document, "final", ATTEMPT_ONE);
    document.onError(
      errorEvent(document, { mode: "final", attempt_id: ATTEMPT_ONE }),
    );

    start(document, "final", ATTEMPT_TWO);
    expect(
      document.onError(
        errorEvent(document, { mode: "final", attempt_id: ATTEMPT_ONE }),
      ),
    ).toBe(false);
    expect(document.status).toBe("running");

    expect(
      document.onReady(
        readyEvent(document, {
          mode: "final",
          attempt_id: ATTEMPT_TWO,
          analysis: analysis("study-analyze"),
          pilot_eligible: null,
        }),
      ),
    ).toBe(true);
    expect(document.finalResult).toBeDefined();
  });

  it("records a failure for the matching attempt and keeps the locked inputs", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);

    expect(document.onError(errorEvent(document))).toBe(true);

    expect(document.status).toBe("failed");
    expect(document.canRetry).toBe(true);
    expect(document.locked.specification_id).toBe("spec-1");
    expect(document.locked.tiers[0]?.run_id).toBe("run-1");
  });

  it("rejects an unknown phase value without changing the phase", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);

    expect(
      document.onProgress(
        progressEvent(document, {
          phase: "not_a_phase" as StudyAnalysisProgressEvent["phase"],
        }),
      ),
    ).toBe(false);
    expect(document.phase).toBe("building_bundle");
  });

  it("sends final with the separate final mapping and locks it", async () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onReady(readyEvent(document));
    primeFinalMapping(document, "final-run-1");
    const api = startApi({
      status: "accepted",
      document_id: "doc-1",
      mode: "final",
      attempt_id: ATTEMPT_TWO,
    });

    expect(await document.runFinal(api)).toBe(true);
    expect(document.attemptId).toBe(ATTEMPT_TWO);
    expect(document.finalMapping.locked).toBe(true);
    expect(payloads(api)[0]).toEqual({
      document_id: "doc-1",
      mode: "final",
      specification_id: "spec-1",
      tier_runs: [{ tier: "small", run_id: "final-run-1" }],
    });
  });

  it("keeps final disabled until the separate mapping preflights", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onReady(readyEvent(document));

    document.finalMapping.selections = { small: "final-run-1" };
    document.finalMapping.preflightStatus = "loading";
    expect(document.canRunFinal).toBe(false);

    document.finalMapping.preflightStatus = "rejected";
    expect(document.canRunFinal).toBe(false);

    document.finalMapping.preflightStatus = "ok";
    expect(document.canRunFinal).toBe(true);
  });

  it("retries final with the locked mapping even after selections change", async () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onReady(readyEvent(document));
    primeFinalMapping(document, "final-run-1");
    const first = startApi({
      status: "accepted",
      document_id: "doc-1",
      mode: "final",
      attempt_id: ATTEMPT_ONE,
    });
    await document.runFinal(first);
    document.onError(errorEvent(document, { mode: "final" }));

    document.finalMapping.selections = { small: "final-run-2" };
    const retry = startApi({
      status: "accepted",
      document_id: "doc-1",
      mode: "final",
      attempt_id: ATTEMPT_TWO,
    });

    expect(await document.retry(retry)).toBe(true);
    expect(payloads(retry)[0]).toEqual({
      document_id: "doc-1",
      mode: "final",
      specification_id: "spec-1",
      tier_runs: [{ tier: "small", run_id: "final-run-1" }],
    });
  });

  it("drops the locked final mapping when pilot runs again", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onReady(readyEvent(document));
    primeFinalMapping(document, "final-run-1");
    document.finalMapping.lockSelections();
    expect(document.finalMapping.locked).toBe(true);

    start(document, "pilot");

    expect(document.finalMapping.locked).toBe(false);
    expect(document.finalMapping.tierSelections()).toEqual([]);
  });

  it("retries a failed pilot with the identical locked mapping", async () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onError(errorEvent(document));
    const api = startApi({
      status: "accepted",
      document_id: "doc-1",
      mode: "pilot",
      attempt_id: ATTEMPT_TWO,
    });

    expect(await document.retry(api)).toBe(true);
    expect(document.attemptId).toBe(ATTEMPT_TWO);
    expect(payloads(api)[0]).toEqual({
      document_id: "doc-1",
      mode: "pilot",
      specification_id: "spec-1",
      tier_runs: [{ tier: "small", run_id: "run-1" }],
    });
  });

  it("cancels the requested document when an accepted retry reply mismatches", async () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onError(errorEvent(document));
    const api = startApi({
      status: "accepted",
      document_id: "doc-2",
      mode: "pilot",
      attempt_id: ATTEMPT_TWO,
    });

    expect(await document.retry(api)).toBe(false);
    expect(api.closeStudyDocument).toHaveBeenCalledWith({
      document_id: "doc-1",
    });
    expect(document.status).toBe("failed");
    expect(document.error).toContain("could not be verified");
    expect(document.attemptId).toBeNull();
  });

  it("cancels the requested document when an accepted reply omits the attempt id", async () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onError(errorEvent(document));
    const api = startApi({
      status: "accepted",
      document_id: "doc-1",
      mode: "pilot",
      attempt_id: null,
    });

    expect(await document.retry(api)).toBe(false);
    expect(api.closeStudyDocument).toHaveBeenCalledWith({
      document_id: "doc-1",
    });
    expect(document.error).toContain("could not be verified");
  });

  it("keeps a retryable error when the ambiguous-start cleanup fails", async () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onError(errorEvent(document));
    const api = startApi({
      status: "accepted",
      document_id: "doc-2",
      mode: "pilot",
      attempt_id: ATTEMPT_TWO,
    });
    vi.mocked(api.closeStudyDocument).mockRejectedValue(new Error("offline"));

    expect(await document.retry(api)).toBe(false);
    expect(document.status).toBe("failed");
    expect(document.error).toContain("could not be cancelled");
    expect(document.canRetry).toBe(true);
    expect(document.locked.tiers[0]?.run_id).toBe("run-1");
  });

  it("clears an earlier pilot and its final result when pilot runs again", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onReady(readyEvent(document));
    start(document, "final");
    document.onReady(
      readyEvent(document, { mode: "final", pilot_eligible: null }),
    );

    start(document);

    expect(document.pilotResult).toBeUndefined();
    expect(document.finalResult).toBeUndefined();
  });

  it("keeps the eligible pilot when final runs again", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onReady(readyEvent(document));

    start(document, "final");

    expect(document.pilotResult).toBeDefined();
    expect(document.finalResult).toBeUndefined();
  });

  it("offers only the retry after a final failure", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onReady(readyEvent(document));
    start(document, "final");
    document.onError(errorEvent(document, { mode: "final" }));

    expect(document.canRunFinal).toBe(false);
    expect(document.canRetry).toBe(true);
    expect(document.retryLabel).toBe("Retry final analysis");
    expect(document.pilotEligible).toBe(true);
  });

  it("requests the exact result bytes and tracks the download request", async () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    const archive = base64Of([0x00, 0xff, 0x10, 0x80, 0x7f]);
    document.onReady(readyEvent(document, { archive }));

    expect(document.downloadPendingModes).toEqual(["pilot"]);
    expect(document.downloadResult("pilot")).toBe(true);

    const blob = vi.mocked(URL.createObjectURL).mock.calls[0]?.[0] as Blob;
    expect(new Uint8Array(await blob.arrayBuffer())).toEqual(
      new Uint8Array([0x00, 0xff, 0x10, 0x80, 0x7f]),
    );
    expect(document.downloadPendingModes).toEqual([]);
  });

  it("does not mark the download requested for an invalid archive", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);
    document.onReady(readyEvent(document, { archive: "!!not base64!!" }));

    expect(document.downloadResult("pilot")).toBe(false);
    expect(document.downloadPendingModes).toEqual(["pilot"]);
    expect(document.error).toContain("not valid");
    expect(URL.createObjectURL).not.toHaveBeenCalled();
  });

  it("warns before closing a running or download-pending document", () => {
    const document = new StudyDocument("doc-1", locked());

    expect(document.closeWarning).toBeNull();

    start(document);
    expect(document.closeWarning).toContain("cancelled");

    document.onReady(readyEvent(document));
    expect(document.closeWarning).toContain("download has not been requested");

    document.downloadResult("pilot");
    expect(document.closeWarning).toBeNull();
  });

  it("keeps the document visible with a retryable close error", () => {
    const document = new StudyDocument("doc-1", locked());
    start(document);

    document.markClosing();
    expect(document.closing).toBe(true);

    document.markCloseFailed("The server did not confirm the close.");
    expect(document.closing).toBe(false);
    expect(document.closeError).toContain("did not confirm");
  });
});
