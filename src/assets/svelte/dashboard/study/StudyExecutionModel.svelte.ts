import {
  studyApprovals,
  studyLifecycle,
  studyOutcomes,
  studyStates,
  studyTiers,
} from "../../contracts.generated/dashboard/study";
import type {
  ContinueFinished,
  Error as StudyError,
  ExecutionEvent,
  PilotResult,
  Progress,
  Result,
  Status,
} from "../../contracts.generated/dashboard/study";
import type { DashboardApi } from "../dashboard-api";

export function errorText(error: StudyError | null | undefined): string {
  return (
    error?.issues
      .map(
        (issue) =>
          `${issue.path.length ? issue.path.join(".") + ": " : ""}${issue.code}: ${issue.message}`,
      )
      .join("\n") ?? ""
  );
}

export class StudyExecutionModel {
  readonly executionId: string;
  readonly documentId: string;
  private api: DashboardApi;
  status = $state.raw<Status | null>(null);
  progress = $state.raw<Progress | null>(null);
  pilot = $state.raw<PilotResult | null>(null);
  result = $state.raw<Result | null>(null);
  resultError = $state.raw<StudyError | null>(null);
  error = $state.raw<StudyError | null>(null);
  message = $state("");
  pendingRequestId = $state<string | null>(null);
  commandPending = $state(false);
  attention = $state(false);
  view = $state<"status" | "pilot" | "results">("status");
  candidateId = $state("");
  overrideConfirmed = $state(false);
  presentation = $state({
    resultTab: "comparisons",
    tier: "all",
    budget: "all",
    alternative: "all",
    timingTier: studyTiers[0] as string,
    unit: "s",
    pilotCandidateId: "",
    selectedComparison: "",
  });

  restorePresentation(value: unknown): void {
    if (!value || typeof value !== "object") return;
    for (const key of Object.keys(
      this.presentation,
    ) as (keyof typeof this.presentation)[]) {
      const field = (value as Record<string, unknown>)[key];
      if (typeof field === "string" && field.length <= 1_000)
        this.presentation[key] = field;
    }
    if (!["comparisons", "timing"].includes(this.presentation.resultTab))
      this.presentation.resultTab = "comparisons";
    if (!["s", "ms", "μs"].includes(this.presentation.unit))
      this.presentation.unit = "s";
    if (!studyTiers.some((tier) => tier === this.presentation.timingTier))
      this.presentation.timingTier = studyTiers[0];
  }
  filteredComparisons = $derived(
    this.result?.comparisons.filter(
      (comparison) =>
        (this.presentation.tier === "all" ||
          comparison.identity.tier === this.presentation.tier) &&
        (this.presentation.budget === "all" ||
          String(comparison.identity.budget) === this.presentation.budget) &&
        (this.presentation.alternative === "all" ||
          comparison.identity.alternative === this.presentation.alternative),
    ) ?? [],
  );
  selectedComparison = $derived(
    this.filteredComparisons.find(
      (comparison) =>
        JSON.stringify(comparison.identity) ===
        this.presentation.selectedComparison,
    ),
  );

  private watchId: string | null = null;
  private sequence = 0;
  private snapshotVersion = 0;
  private disposed = false;
  private loadingReports = new Set<"pilot" | "result">();

  constructor(
    executionId: string,
    documentId: string,
    api: DashboardApi,
    status?: Status,
  ) {
    this.executionId = executionId;
    this.documentId = documentId;
    this.api = api;
    if (status) this.status = status;
  }

  get lifecycle() {
    return this.status ? studyLifecycle[this.status.state] : null;
  }

  get canContinue(): boolean {
    return (
      !this.disposed &&
      !!this.lifecycle?.canContinue &&
      !this.pendingRequestId &&
      !this.commandPending
    );
  }
  get canCancel(): boolean {
    return (
      !this.disposed && !!this.lifecycle?.canCancel && !this.commandPending
    );
  }
  get notice(): string {
    switch (this.status?.state) {
      case studyStates.awaiting_final:
        return "Pilot accepted. Review the report and explicitly approve Final collection.";
      case studyStates.succeeded:
        return "Final result is stored. Review comparisons and measured timing.";
      case studyStates.failed:
        return "Execution failed. The accepted context remains available. Start a separate execution to try again.";
      case studyStates.cancelled:
        return "Execution cancelled. Dispatched effects can still finish; the execution remains cancelled.";
      default:
        return this.message;
    }
  }

  async watch(): Promise<void> {
    if (this.watchId || this.disposed || this.lifecycle?.terminal) return;
    const id = crypto.randomUUID();
    this.watchId = id;
    this.sequence = 0;
    try {
      const reply = await this.api.studyRequest("watch_study_execution", {
        document_id: this.documentId,
        execution_id: this.executionId,
        watch_id: id,
      });
      if (this.disposed || this.watchId !== id) return;
      if (reply.status !== "ok") {
        this.error = reply.error ?? null;
        this.watchId = null;
      }
    } catch {
      if (this.disposed || this.watchId !== id) return;
      this.watchId = null;
      this.message = "Observation ended. Refresh to reconnect.";
    }
  }

  async refresh(): Promise<void> {
    if (this.disposed) return;
    const version = ++this.snapshotVersion;
    try {
      const reply = await this.api.studyRequest("fetch_study_status", {
        execution_id: this.executionId,
      });
      if (!this.isCurrent(version)) return;
      if (reply.execution) {
        if (
          this.acceptStatus(reply.execution, false) &&
          reply.progress?.execution_id === this.executionId
        )
          this.progress = reply.progress;
      } else this.error = reply.error ?? null;
      await this.watch();
      await this.loadReports();
    } catch {
      if (this.isCurrent(version))
        this.message = "Could not refresh this execution. Try Refresh.";
    }
  }

  observed(event: ExecutionEvent, reviewed: boolean): boolean {
    if (
      this.disposed ||
      event.execution_id !== this.executionId ||
      event.document_id !== this.documentId ||
      event.watch_id !== this.watchId ||
      event.sequence <= this.sequence
    )
      return false;
    this.sequence = event.sequence;
    const accepted = this.acceptStatus(event.status, !reviewed);
    if (accepted) this.progress = event.progress;
    if (reviewed) this.attention = false;
    void this.loadReports();
    return accepted;
  }

  private isCurrent(version: number): boolean {
    return !this.disposed && version === this.snapshotVersion;
  }

  private acceptStatus(status: Status, notify: boolean): boolean {
    if (status.execution_id !== this.executionId) return false;
    const previous = this.status?.state;
    const before = previous ? studyLifecycle[previous] : null;
    const next = studyLifecycle[status.state];
    if (before?.terminal && previous !== status.state) return false;
    if (
      before?.order != null &&
      next.order != null &&
      before.order > next.order
    )
      return false;
    this.status = status;
    this.snapshotVersion++;
    if (next.terminal) {
      this.pendingRequestId = null;
      this.endWatch();
    }
    if (notify && previous && previous !== status.state && next.attention)
      this.attention = true;
    return true;
  }

  private async loadReports(): Promise<void> {
    if (this.status?.pilot_outcome) await this.readReport("pilot");
    if (this.status?.state === studyStates.succeeded) await this.readResult();
  }

  readResult(): Promise<void> {
    return this.readReport("result");
  }

  private async readReport(kind: "pilot" | "result"): Promise<void> {
    if (this.disposed || this[kind] || this.loadingReports.has(kind)) return;
    this.loadingReports.add(kind);
    try {
      const reply = await this.api.studyRequest(
        kind === "pilot" ? "fetch_study_pilot_result" : "fetch_study_result",
        { execution_id: this.executionId },
      );
      if (this.disposed) return;
      if (kind === "pilot") {
        if (reply.pilot) this.pilot = reply.pilot;
        else this.error = reply.error ?? null;
      } else {
        if (reply.result) this.result = reply.result;
        this.resultError = reply.error ?? null;
      }
    } catch {
      const subject =
        kind === "pilot" ? "accepted Pilot report" : "stored Final result";
      this.message = `Could not load the ${subject}. Use Refresh.`;
    } finally {
      this.loadingReports.delete(kind);
    }
  }

  async continue(): Promise<void> {
    if (!this.canContinue) return;
    const id = crypto.randomUUID();
    this.pendingRequestId = id;
    this.error = null;
    try {
      const reply = await this.api.studyRequest("continue_study_execution", {
        document_id: this.documentId,
        execution_id: this.executionId,
        request_id: id,
      });
      if (reply.status !== "accepted" || reply.request_id !== id) {
        if (this.pendingRequestId === id) this.pendingRequestId = null;
        this.error = reply.error ?? null;
      }
    } catch {
      if (this.pendingRequestId === id) this.pendingRequestId = null;
      this.message =
        "The continuation acknowledgement was lost. Refresh accepted status before continuing.";
    }
  }

  finished(event: ContinueFinished): void {
    if (
      this.disposed ||
      event.request_id !== this.pendingRequestId ||
      event.execution_id !== this.executionId
    )
      return;
    this.pendingRequestId = null;
    if (event.status) this.acceptStatus(event.status, true);
    this.error = event.error ?? null;
    this.message =
      "Continue returned. Active work requires another explicit Continue to advance.";
    void this.refresh();
  }

  async approve(): Promise<void> {
    if (
      this.commandPending ||
      this.status?.state !== studyStates.awaiting_final ||
      !this.pilot
    )
      return;
    const recommended =
      this.pilot.outcome.outcome === studyOutcomes.recommended;
    if (!recommended && !this.overrideConfirmed) return;
    await this.command("approve_study_final", {
      approval: recommended
        ? studyApprovals.recommended
        : studyApprovals.override_insufficient,
      candidate_id: recommended ? undefined : this.candidateId,
    });
  }

  async cancel(): Promise<void> {
    if (!this.canCancel) return;
    await this.command("cancel_study_execution");
  }

  private async command(
    event: "approve_study_final" | "cancel_study_execution",
    payload = {},
  ): Promise<void> {
    this.commandPending = true;
    this.error = null;
    try {
      const reply = await this.api.studyRequest(event, {
        execution_id: this.executionId,
        ...payload,
      });
      if (reply.execution) this.acceptStatus(reply.execution, false);
      else this.error = reply.error ?? null;
      await this.refresh();
    } catch {
      this.message =
        "The command reply was lost. Refresh accepted status before another command.";
    } finally {
      this.commandPending = false;
    }
  }

  reconnect(): void {
    this.watchId = null;
    this.sequence = 0;
    this.pendingRequestId = null;
    this.commandPending = false;
    this.progress = null;
    void this.refresh();
  }

  private endWatch(): void {
    const id = this.watchId;
    if (!id) return;
    this.watchId = null;
    void this.api
      .studyRequest("unwatch_study_execution", {
        document_id: this.documentId,
        watch_id: id,
      })
      .catch(() => {});
  }

  dispose(): void {
    this.disposed = true;
    this.watchId = null;
    this.pendingRequestId = null;
  }
}
