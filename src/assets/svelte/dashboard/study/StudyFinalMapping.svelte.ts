import type {
  StudyRunError,
  StudyTierRunSummary,
  StudyTierSelection,
} from "../../contracts.generated/dashboard/evaluation";
import type { DashboardApi } from "../dashboard-api";
import { tierSelectionsFrom, visibleStudyRunErrors } from "./study-types";

export type FinalPreflightStatus = "idle" | "loading" | "ok" | "rejected";

/**
 * Browser state for the separate Final tier mapping.
 *
 * Final analysis runs on its own completed runs from the `final_seed_schedule`,
 * not on the Pilot runs. This model loads the Final-compatible runs per
 * declared tier, runs one server preflight for the mapping, and locks the
 * mapping when the first Final start is accepted. A Final retry then reuses the
 * locked mapping, so a changed mapping cannot reuse the eligible Pilot.
 *
 * The Pilot run IDs are excluded from every picker, and the server repeats the
 * overlap check, so Pilot and Final evidence stays disjoint.
 */
export class StudyFinalMapping {
  api: DashboardApi | undefined;
  readonly specification_id: string;
  readonly tiers: readonly string[];
  readonly pilotRunIds: readonly string[];

  selections = $state.raw<Record<string, string>>({});
  runsByTier = $state.raw<Record<string, StudyTierRunSummary[]>>({});
  required_inputs = $state("");
  isLoading = $state(false);
  pickerTier = $state<string | null>(null);
  preflightStatus = $state<FinalPreflightStatus>("idle");
  preflightErrors = $state.raw<StudyRunError[]>([]);
  locked = $state(false);
  private lockedTierRuns = $state.raw<StudyTierSelection[]>([]);

  private runsRequestId = $state(0);
  private preflightRequestId = $state(0);

  constructor(
    specification_id: string,
    tiers: readonly string[],
    pilotRunIds: readonly string[],
  ) {
    this.specification_id = specification_id;
    this.tiers = tiers;
    this.pilotRunIds = pilotRunIds;
  }

  get pickerOpen(): boolean {
    return this.pickerTier !== null;
  }

  get pickerRuns(): StudyTierRunSummary[] {
    return this.pickerTier ? this.availableRuns(this.pickerTier) : [];
  }

  get mappedCount(): number {
    return this.tiers.filter((tier) => Boolean(this.selections[tier])).length;
  }

  get missingTiers(): string[] {
    return this.tiers.filter((tier) => !this.selections[tier]);
  }

  get hasMissingSelections(): boolean {
    return this.missingTiers.length > 0;
  }

  /** Server errors excluding generic missing-tier duplicates. */
  get visiblePreflightErrors(): StudyRunError[] {
    return visibleStudyRunErrors(
      this.preflightErrors,
      this.hasMissingSelections,
    );
  }

  missingSelectionMessage(tier: string): string | null {
    if (this.selections[tier]) return null;
    return this.availableRuns(tier).length === 0
      ? "No unused completed run remains for this tier."
      : "Select one completed run for this tier.";
  }

  get complete(): boolean {
    return (
      this.tiers.length > 0 &&
      this.tiers.every((tier) => Boolean(this.selections[tier]))
    );
  }

  get hasDuplicateRun(): boolean {
    const runIds = this.tiers.flatMap((tier) => {
      const runId = this.selections[tier];
      return runId ? [runId] : [];
    });
    return runIds.some((runId, index) => runIds.indexOf(runId) !== index);
  }

  get hasEligibleRuns(): boolean {
    return this.tiers.some((tier) => (this.runsByTier[tier]?.length ?? 0) > 0);
  }

  /** True when the locked Final mapping can start the analysis. */
  get canRun(): boolean {
    return (
      !this.locked &&
      this.complete &&
      !this.hasDuplicateRun &&
      this.preflightStatus === "ok"
    );
  }

  availableRuns(tier: string): StudyTierRunSummary[] {
    return (this.runsByTier[tier] ?? []).filter(
      (run) =>
        this.selections[tier] === run.id ||
        (!this.pilotRunIds.includes(run.id) &&
          !this.runUsedByAnotherTier(tier, run.id)),
    );
  }

  runFor(tier: string): StudyTierRunSummary | undefined {
    const runId = this.selections[tier];
    return runId
      ? this.runsByTier[tier]?.find((run) => run.id === runId)
      : undefined;
  }

  runUsedByAnotherTier(tier: string, runId: string): boolean {
    return Object.entries(this.selections).some(
      ([otherTier, otherRun]) => otherTier !== tier && otherRun === runId,
    );
  }

  /** Loads the Final runs once, unless a request is active or they exist. */
  async ensureRunsLoaded(): Promise<void> {
    if (this.isLoading || Object.keys(this.runsByTier).length > 0) return;
    await this.loadRuns();
  }

  /** Loads the Final-compatible runs for every declared tier. */
  async loadRuns(): Promise<void> {
    const api = this.api;
    const requestId = ++this.runsRequestId;
    const specification_id = this.specification_id;
    if (!api || this.tiers.length === 0) {
      this.runsByTier = {};
      this.required_inputs = "";
      this.isLoading = false;
      return;
    }

    this.isLoading = true;
    try {
      const entries = await Promise.all(
        this.tiers.map(async (tier) => {
          const reply = await api.listStudyTierRuns({
            specification_id,
            tier,
            mode: "final",
          });
          return [tier, reply.runs, reply.required_inputs ?? ""] as const;
        }),
      );
      if (requestId !== this.runsRequestId) return;
      this.runsByTier = Object.fromEntries(
        entries.map(([tier, runs]) => [tier, runs]),
      );
      this.required_inputs = entries[0]?.[2] ?? "";
      this.refreshPreflight();
    } catch {
      if (requestId !== this.runsRequestId) return;
      this.runsByTier = {};
      this.required_inputs = "";
    } finally {
      if (requestId === this.runsRequestId) this.isLoading = false;
    }
  }

  openPicker(tier: string): void {
    if (this.locked) return;
    this.pickerTier = tier;
  }

  closePicker(): void {
    this.pickerTier = null;
  }

  selectRun(tier: string, runId: string): boolean {
    if (this.locked) return false;
    if (
      this.pilotRunIds.includes(runId) ||
      this.runUsedByAnotherTier(tier, runId)
    ) {
      return false;
    }
    this.selections = { ...this.selections, [tier]: runId };
    this.pickerTier = null;
    this.refreshPreflight();
    return true;
  }

  clearRun(tier: string): void {
    if (this.locked) return;
    const { [tier]: _removed, ...rest } = this.selections;
    this.selections = rest;
    this.refreshPreflight();
  }

  refreshPreflight(): void {
    const api = this.api;
    const requestId = ++this.preflightRequestId;
    this.preflightErrors = [];
    if (!api || this.locked) {
      this.preflightStatus = "idle";
      return;
    }
    this.preflightStatus = "loading";
    void api
      .preflightStudy({
        specification_id: this.specification_id,
        mode: "final",
        tier_runs: this.tierSelections(),
      })
      .then((reply) => {
        if (requestId !== this.preflightRequestId) return;
        this.preflightStatus = reply.status === "ok" ? "ok" : "rejected";
        this.preflightErrors = reply.errors;
      })
      .catch(() => {
        if (requestId !== this.preflightRequestId) return;
        this.preflightStatus = "idle";
        this.preflightErrors = [];
      });
  }

  /** Wire selections for the Final start and preflight requests. */
  tierSelections(): StudyTierSelection[] {
    if (this.locked) return [...this.lockedTierRuns];
    return tierSelectionsFrom(this.tiers, this.selections);
  }

  /** Locks the accepted Final mapping, so a retry reuses the same evidence. */
  lockSelections(): void {
    if (this.locked) return;
    this.lockedTierRuns = this.tierSelections();
    this.locked = true;
  }

  /** Clears the mapping and its preflight, for example after a new Pilot. */
  reset(): void {
    this.selections = {};
    this.runsByTier = {};
    this.required_inputs = "";
    this.pickerTier = null;
    this.preflightStatus = "idle";
    this.preflightErrors = [];
    this.locked = false;
    this.lockedTierRuns = [];
    this.runsRequestId += 1;
    this.preflightRequestId += 1;
    this.isLoading = false;
  }
}
