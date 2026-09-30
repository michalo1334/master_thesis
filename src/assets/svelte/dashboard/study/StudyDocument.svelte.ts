import type {
  StartStudyAnalysisPayload,
  StartStudyAnalysisReply,
  StudyAnalysisErrorEvent,
  StudyAnalysisProgressEvent,
  StudyAnalysisReadyEvent,
  StudyRunError,
} from "../../contracts.generated/dashboard/evaluation";
import type { DashboardApi } from "../dashboard-api";
import { WorkspaceDocumentBase } from "../workspace/WorkspaceDocument.svelte";
import { StudyFinalMapping } from "./StudyFinalMapping.svelte";
import { requestStudyClose } from "./study-close";
import { downloadStudyResult, studyResultFilename } from "./study-download";
import {
  formatStudyRunError,
  isStudyPhase,
  lockedTierSelections,
  type StudyLockedInputs,
  type StudyMode,
  type StudyPhase,
  type StudyResult,
  type StudyTierMapping,
} from "./study-types";

/**
 * Result of opening the live study document for one locked setup.
 *
 * `created` separates a fresh provisional document from a document that
 * already held the identical locked inputs, so the caller can reuse the
 * running document instead of discarding it.
 */
export interface StudyDocumentOpen {
  readonly document: StudyDocument;
  readonly created: boolean;
}

type StudyStatus = "idle" | "running" | "ready" | "failed";

/**
 * One live study document.
 *
 * The document locks the saved specification identity and the exact tier-run
 * mapping when Pilot starts and never edits them. Progress and results live in
 * the browser session only; the workspace does not persist this document.
 *
 * The document owns every lifecycle transition: the named phase, the Pilot and
 * Final results, the Final gate, the in-place retry, the download request, and
 * the close acknowledgment. Live events reach the document through
 * `onProgress`, `onReady`, and `onError`, which accept an event only when the
 * document id, the running mode, and the running attempt identity all match.
 * The attempt identity comes from the accepted start reply, so a delayed event
 * from an earlier attempt in the same mode cannot settle a retry.
 */
export class StudyDocument extends WorkspaceDocumentBase {
  readonly kind = "study" as const;
  readonly documentLabel = "Study";
  readonly icon = "simulation-report" as const satisfies string;
  readonly id: string;
  readonly title: string;
  readonly locked: StudyLockedInputs;
  readonly finalMapping: StudyFinalMapping;

  // Bound by the document view. The value is not reactive: the effect that
  // calls `attachApi` already reacts to Pilot eligibility and triggers the
  // Final run load, so the reference itself never drives rendering.
  api: DashboardApi | undefined;

  mode = $state<StudyMode | null>(null);
  attemptId = $state<string | null>(null);
  phase = $state<StudyPhase | null>(null);
  status = $state<StudyStatus>("idle");
  error = $state("");
  closeError = $state("");
  closing = $state(false);
  results = $state.raw<Partial<Record<StudyMode, StudyResult>>>({});
  activeResultTab = $state<StudyMode>("pilot");

  constructor(id: string, locked: StudyLockedInputs) {
    super();
    this.id = id;
    this.locked = locked;
    this.title = locked.title;
    this.finalMapping = new StudyFinalMapping(
      locked.specification_id,
      locked.tiers.map((tier) => tier.tier),
      locked.tiers.map((tier) => tier.run_id),
    );
  }

  /**
   * Binds the dashboard API and loads the Final runs once the Pilot is eligible.
   *
   * The workspace renders the document view with the API prop, so the Final
   * mapping can only call the server after this binding.
   */
  attachApi(api?: DashboardApi): void {
    if (api === undefined) return;
    this.api = api;
    this.finalMapping.api = api;
    if (this.pilotEligible && this.finalResult === undefined) {
      void this.finalMapping.ensureRunsLoaded();
    }
  }

  get tierCount(): number {
    return this.locked.tiers.length;
  }

  get running(): boolean {
    return this.status === "running";
  }

  get pilotResult(): StudyResult | undefined {
    return this.results.pilot;
  }

  get finalResult(): StudyResult | undefined {
    return this.results.final;
  }

  get hasResults(): boolean {
    return this.pilotResult !== undefined || this.finalResult !== undefined;
  }

  /** True only for a Pilot with a valid recommendation and no blocking finding. */
  get pilotEligible(): boolean {
    return this.pilotResult?.pilot_eligible === true;
  }

  /** True for a completed Pilot that cannot start Final. */
  get pilotBlocked(): boolean {
    return this.pilotResult !== undefined && !this.pilotEligible;
  }

  get canRunFinal(): boolean {
    return (
      this.pilotEligible &&
      this.status !== "running" &&
      this.status !== "failed" &&
      this.finalResult === undefined &&
      this.finalMapping.canRun
    );
  }

  get canRerunPilot(): boolean {
    return (
      this.pilotBlocked && this.status !== "running" && this.status !== "failed"
    );
  }

  /** True when a service error left the locked inputs available for retry. */
  get canRetry(): boolean {
    return this.status === "failed" && this.mode !== null;
  }

  get retryLabel(): string {
    return this.mode === "final"
      ? "Retry final analysis"
      : "Retry pilot analysis";
  }

  /** Result modes whose download has not been requested yet. */
  get downloadPendingModes(): StudyMode[] {
    return (["pilot", "final"] as const).flatMap((mode) =>
      this.results[mode] && !this.results[mode].downloadRequested ? [mode] : [],
    );
  }

  /**
   * Confirmation text for closing this document, or `null` for a safe close.
   *
   * A running analysis is cancelled and a completed result with no download
   * request is lost, so both warn before the close.
   */
  get closeWarning(): string | null {
    const reasons: string[] = [];
    if (this.running) reasons.push("the running analysis is cancelled");
    const pending = this.downloadPendingModes.map((mode) =>
      mode === "pilot" ? "Pilot" : "Final",
    );
    if (pending.length > 0) {
      reasons.push(
        `the ${pending.join(" and ")} result download has not been requested`,
      );
    }
    return reasons.length > 0
      ? `Close "${this.title}"? ${reasons.join(", and ")}.`
      : null;
  }

  matchesLocks(locked: StudyLockedInputs): boolean {
    return (
      this.locked.specification_id === locked.specification_id &&
      this.locked.specification_version === locked.specification_version &&
      sameTiers(this.locked.tiers, locked.tiers)
    );
  }

  markStarted(mode: StudyMode): void {
    this.mode = mode;
    this.attemptId = null;
    this.status = "running";
    this.phase = "building_bundle";
    this.error = "";
    this.closeError = "";
    this.results = clearResults(this.results, mode);
    this.activeResultTab = mode;
    if (mode === "pilot") this.finalMapping.reset();
  }

  /**
   * Marks a provisional handle that may still own an uncancelled server task.
   *
   * The mode is set so the workspace close path sends a cancellation request,
   * and the error stays visible until the user closes the document.
   */
  markUnconfirmedStart(mode: StudyMode, message: string): void {
    this.markStarted(mode);
    this.markError(message);
  }

  markRejected(errors: readonly StudyRunError[]): void {
    const [first] = errors;
    this.markError(
      first ? formatStudyRunError(first) : "The study request was rejected.",
    );
  }

  markError(message: string): void {
    this.status = "failed";
    this.error = message;
  }

  markClosing(): void {
    this.closing = true;
    this.closeError = "";
  }

  /** Keeps the document visible with a retryable close error. */
  markCloseFailed(message: string): void {
    this.closing = false;
    this.closeError = message;
  }

  applyPhase(phase: StudyPhase): void {
    if (!this.running) return;
    this.phase = phase;
  }

  /** Applies one phase event for the matching running attempt. */
  onProgress(payload: StudyAnalysisProgressEvent): boolean {
    if (
      !this.matchesAttempt(
        payload.document_id,
        payload.mode,
        payload.attempt_id,
      )
    )
      return false;
    if (!isStudyPhase(payload.phase)) return false;
    this.applyPhase(payload.phase);
    return true;
  }

  /** Stores one completed result for the matching running attempt. */
  onReady(payload: StudyAnalysisReadyEvent): boolean {
    if (
      !this.matchesAttempt(
        payload.document_id,
        payload.mode,
        payload.attempt_id,
      )
    )
      return false;
    const mode = payload.mode;
    this.status = "ready";
    this.phase = "complete";
    this.error = "";
    this.results = {
      ...this.results,
      [mode]: {
        analysis: payload.analysis,
        archive: payload.archive,
        pilot_eligible: payload.pilot_eligible,
        downloadRequested: false,
      },
    };
    this.activeResultTab = mode;
    if (mode === "pilot" && this.pilotEligible) {
      void this.finalMapping.ensureRunsLoaded();
    }
    return true;
  }

  /** Records one failure for the matching running attempt and keeps the locks. */
  onError(payload: StudyAnalysisErrorEvent): boolean {
    if (
      !this.matchesAttempt(
        payload.document_id,
        payload.mode,
        payload.attempt_id,
      )
    )
      return false;
    this.markError(formatStudyRunError(payload.error));
    return true;
  }

  /** Starts Final with separate evidence under the server-held Pilot gate. */
  async runFinal(api?: DashboardApi): Promise<boolean> {
    if (api) this.attachApi(api);
    if (!this.canRunFinal) return false;
    return this.startAttempt(this.api, "final");
  }

  /** Repeats the exact failed attempt with the same locked inputs. */
  async retry(api?: DashboardApi): Promise<boolean> {
    if (api) this.attachApi(api);
    if (!this.canRetry || this.mode === null) return false;
    return this.startAttempt(this.api, this.mode);
  }

  /**
   * Repeats the identical Pilot after an insufficient or non-informative one.
   *
   * Deterministic inputs should reproduce the same stop condition.
   */
  async rerunPilot(api?: DashboardApi): Promise<boolean> {
    if (api) this.attachApi(api);
    if (!this.canRerunPilot) return false;
    return this.startAttempt(this.api, "pilot");
  }

  /**
   * Requests the exact ZIP bytes and records the download request.
   *
   * Invalid base64 reports `false` and leaves `downloadRequested` unchanged, so
   * a close warning still reports that the download never started.
   */
  downloadResult(mode: StudyMode): boolean {
    const result = this.results[mode];
    if (!result) return false;
    const requested = downloadStudyResult(
      result.archive,
      studyResultFilename(
        this.locked.study_id,
        this.locked.specification_version,
        mode,
      ),
    );
    if (!requested) {
      this.error =
        "The result archive is not valid, so the download did not start.";
      return false;
    }
    this.results = {
      ...this.results,
      [mode]: { ...result, downloadRequested: true },
    };
    return true;
  }

  private matchesAttempt(
    documentId: string,
    wireMode: string,
    wireAttemptId: string,
  ): boolean {
    return (
      this.running &&
      this.id === documentId &&
      this.mode === wireMode &&
      this.attemptId !== null &&
      this.attemptId === wireAttemptId
    );
  }

  private async startAttempt(
    api: DashboardApi | undefined,
    mode: StudyMode,
  ): Promise<boolean> {
    if (!api) {
      this.markError("The dashboard connection is unavailable.");
      return false;
    }

    this.markStarted(mode);
    try {
      const reply = await api.startStudyAnalysis(this.startPayload(mode));
      if (this.mode !== mode || !this.running) return false;

      const attemptId = this.acceptedAttemptId(reply, mode);
      if (attemptId !== null) {
        this.attemptId = attemptId;
        if (mode === "final") this.finalMapping.lockSelections();
        return true;
      }
      if (reply.status === "accepted") {
        await this.recoverAmbiguousStart(api);
        return false;
      }
      this.markRejected(reply.errors);
      return false;
    } catch {
      this.markError("Unable to reach the dashboard. Try again.");
      return false;
    }
  }

  /**
   * Confirms one accepted reply against this exact document, mode, and attempt.
   *
   * A reply for another document or mode, or an accepted reply with no attempt
   * identity, is ambiguous. Returns the confirmed attempt identity, or `null`.
   */
  private acceptedAttemptId(
    reply: StartStudyAnalysisReply,
    mode: StudyMode,
  ): string | null {
    if (reply.status !== "accepted") return null;
    if (reply.document_id !== this.id || reply.mode !== mode) return null;
    const attemptId = reply.attempt_id;
    return typeof attemptId === "string" && attemptId.length > 0
      ? attemptId
      : null;
  }

  /**
   * Cleans up after an accepted reply whose identifiers did not match.
   *
   * The request named this document, so cancellation targets this exact id.
   * A `closed` or `not_found` acknowledgment means no task remains. Otherwise
   * the document keeps a visible error and the client handle, and closing it
   * again retries the cancellation.
   */
  private async recoverAmbiguousStart(api: DashboardApi): Promise<void> {
    this.attemptId = null;
    const confirmed = await requestStudyClose(api, this.id);
    if (confirmed) {
      this.markError(
        "The analysis reply could not be verified. No analysis is running. Try again.",
      );
      return;
    }
    this.markError(
      "The analysis reply could not be verified and the server task could not be cancelled. Close this document to retry cancellation.",
    );
  }

  private startPayload(mode: StudyMode): StartStudyAnalysisPayload {
    return mode === "pilot"
      ? {
          document_id: this.id,
          mode,
          specification_id: this.locked.specification_id,
          tier_runs: lockedTierSelections(this.locked),
        }
      : {
          document_id: this.id,
          mode,
          specification_id: this.locked.specification_id,
          tier_runs: this.finalMapping.tierSelections(),
        };
  }
}

// A new Pilot attempt invalidates any earlier Pilot eligibility and its Final
// result. A Final attempt replaces only the Final result.
function clearResults(
  results: Partial<Record<StudyMode, StudyResult>>,
  mode: StudyMode,
): Partial<Record<StudyMode, StudyResult>> {
  if (mode === "pilot") return {};
  const { final: _cleared, ...rest } = results;
  return rest;
}

function sameTiers(
  left: readonly StudyTierMapping[],
  right: readonly StudyTierMapping[],
): boolean {
  return (
    left.length === right.length &&
    left.every(
      (tier, index) =>
        tier.tier === right[index]?.tier &&
        tier.run_id === right[index]?.run_id,
    )
  );
}
