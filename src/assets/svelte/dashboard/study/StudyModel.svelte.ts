import type {
  DescribeStudySpecificationReply,
  ManifestError,
  PreflightStudyReply,
  SaveStudySpecificationReply,
  StartStudyAnalysisReply,
  StudyRunError,
  StudySpecificationSummary,
  StudyTierRunSummary,
  StudyTierSelection,
} from "../../contracts.generated/dashboard/evaluation";
import type { DashboardApi } from "../dashboard-api";
import type { StudyDocument, StudyDocumentOpen } from "./StudyDocument.svelte";
import { requestStudyClose } from "./study-close";
import {
  createDefaultStudySpecification,
  declaredTierLabels,
  formatStudyRunError,
  tierSelectionsFrom,
  visibleStudyRunErrors,
  type StudyLockedInputs,
  type StudyTab,
  type StudyTierMapping,
} from "./study-types";

export type PreflightStatus = "idle" | "loading" | "ok" | "rejected";

/**
 * Dialog model for saved study specifications and tier-run mapping.
 *
 * Saved versions are immutable, so a changed specification saves as a new
 * version. The title is immutable saved metadata, so a title edit invalidates
 * the version exactly like a JSON edit: the mapping and preflight clear and
 * Pilot stays blocked until Save as new version.
 *
 * Tier runs load per declared tier with one scoped `(specification, tier)`
 * request. The model runs one server preflight per saved version and mapping
 * change and ignores stale replies by request identity.
 */
export class StudyModel {
  open = $state(false);
  specifications = $state.raw<StudySpecificationSummary[]>([]);
  selectedId = $state<string | null>(null);
  title = $state("");
  editorText = $state("");
  errors = $state.raw<ManifestError[]>([]);
  statusMessage = $state("");
  isLoading = $state(false);
  isSaving = $state(false);
  isStarting = $state(false);
  activeTab = $state<StudyTab>("json");

  previewContent = $state<Record<string, unknown> | null>(null);
  previewReply = $state<DescribeStudySpecificationReply | null>(null);
  previewNotice = $state("");
  isLoadingPreview = $state(false);
  private previewRequestId = $state(0);
  private specificationsRequestId = $state(0);
  private selectionRequestId = $state(0);

  savedTiers = $state.raw<string[]>([]);
  private savedTitle = $state("");
  private savedEditorText = $state("");

  tierRunsByTier = $state.raw<Record<string, StudyTierRunSummary[]>>({});
  isLoadingRuns = $state(false);
  private tierRunsRequestId = $state(0);
  selections = $state.raw<Record<string, string>>({});
  pickerTier = $state<string | null>(null);
  required_inputs = $state("");
  preflightStatus = $state<PreflightStatus>("idle");
  preflightErrors = $state.raw<StudyRunError[]>([]);
  private preflightRequestId = $state(0);

  openStudyDocument:
    ((locked: StudyLockedInputs) => StudyDocumentOpen) | undefined;
  activateStudyDocument: ((document: StudyDocument) => void) | undefined;
  discardStudyDocument: ((document: StudyDocument) => void) | undefined;
  onOpenEvaluationManifest: (() => void) | undefined;

  readonly api: DashboardApi;

  constructor(api: DashboardApi) {
    this.api = api;
  }

  get isBusy(): boolean {
    return this.isLoading || this.isSaving || this.isStarting;
  }

  get selectedSpecification(): StudySpecificationSummary | undefined {
    return this.specifications.find(
      (specification) => specification.id === this.selectedId,
    );
  }

  /** True only while the title and editor match a saved immutable version. */
  get isSavedVersion(): boolean {
    return (
      this.selectedId !== null &&
      this.title === this.savedTitle &&
      this.editorText === this.savedEditorText
    );
  }

  get hasUnsavedChanges(): boolean {
    return (
      this.selectedId === null ||
      this.title !== this.savedTitle ||
      this.editorText !== this.savedEditorText
    );
  }

  get declaredTiers(): readonly string[] {
    return this.isSavedVersion ? this.savedTiers : [];
  }

  /** Exact saved identity that the Run tab would execute. */
  get savedVersionLabel(): string {
    const specification = this.isSavedVersion
      ? this.selectedSpecification
      : undefined;
    return specification
      ? `${specification.study_id} v${specification.specification_version}`
      : "";
  }

  get mappedCount(): number {
    return this.declaredTiers.filter((tier) => this.selections[tier]).length;
  }

  get missingTiers(): string[] {
    return this.declaredTiers.filter((tier) => !this.selections[tier]);
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

  get mappingComplete(): boolean {
    const tiers = this.declaredTiers;
    return (
      tiers.length > 0 && tiers.every((tier) => Boolean(this.selections[tier]))
    );
  }

  get hasDuplicateRun(): boolean {
    const runIds = this.declaredTiers.flatMap((tier) => {
      const runId = this.selections[tier];
      return runId ? [runId] : [];
    });
    return runIds.some((runId, index) => runIds.indexOf(runId) !== index);
  }

  /**
   * True when Save would store a new immutable identity.
   *
   * Editing a saved version keeps its `study_id` and `specification_version`,
   * so the server would always answer `immutable_conflict`. Save is disabled
   * for that case and Save as new version is the valid action.
   */
  get canSave(): boolean {
    return this.hasContent && !this.isBusy && !this.saveWouldConflict;
  }

  get canSaveAsNewVersion(): boolean {
    return (
      this.selectedId !== null &&
      this.hasUnsavedChanges &&
      this.hasContent &&
      !this.isBusy
    );
  }

  /**
   * True when the selected saved version has any edit.
   *
   * Editing a selected saved specification disables Save even when the user
   * also edited `study_id` or `specification_version` by hand: those fields are
   * immutable saved identity, so only Save as new version may persist the
   * edit. A new specification has no selected version and keeps Save enabled.
   */
  get saveWouldConflict(): boolean {
    return this.selectedId !== null && this.hasUnsavedChanges;
  }

  private get hasContent(): boolean {
    return this.title.trim() !== "" && this.editorText.trim() !== "";
  }

  get canStartPilot(): boolean {
    return (
      this.isSavedVersion &&
      this.selectedId !== null &&
      this.mappingComplete &&
      !this.hasDuplicateRun &&
      this.preflightStatus === "ok" &&
      !this.isBusy
    );
  }

  get pickerOpen(): boolean {
    return this.pickerTier !== null;
  }

  /** Eligible runs the picker offers for one tier, minus runs used elsewhere. */
  get pickerRuns(): StudyTierRunSummary[] {
    return this.pickerTier ? this.availableRuns(this.pickerTier) : [];
  }

  availableRuns(tier: string): StudyTierRunSummary[] {
    return (this.tierRunsByTier[tier] ?? []).filter(
      (run) =>
        this.selections[tier] === run.id ||
        !this.runUsedByAnotherTier(tier, run.id),
    );
  }

  /** True while any declared tier still has an eligible completed run. */
  get hasEligibleRuns(): boolean {
    return this.declaredTiers.some(
      (tier) => (this.tierRunsByTier[tier]?.length ?? 0) > 0,
    );
  }

  runFor(tier: string): StudyTierRunSummary | undefined {
    const runId = this.selections[tier];
    return runId
      ? this.tierRunsByTier[tier]?.find((run) => run.id === runId)
      : undefined;
  }

  runUsedByAnotherTier(tier: string, runId: string): boolean {
    return Object.entries(this.selections).some(
      ([otherTier, otherRun]) => otherTier !== tier && otherRun === runId,
    );
  }

  async openDialog(): Promise<void> {
    this.open = true;
    await this.loadSpecifications();
  }

  closeDialog(): void {
    if (this.isBusy) return;
    this.open = false;
    this.pickerTier = null;
  }

  openEvaluationManifest(): void {
    this.open = false;
    this.pickerTier = null;
    this.onOpenEvaluationManifest?.();
  }

  async loadSpecifications(): Promise<void> {
    const requestId = ++this.specificationsRequestId;
    this.isLoading = true;
    try {
      const reply = await this.api.listStudySpecifications();
      if (requestId !== this.specificationsRequestId) return;
      this.specifications = reply.specifications;
      if (
        this.selectedId &&
        !this.specifications.some(
          (specification) => specification.id === this.selectedId,
        )
      ) {
        this.clearSelection();
      }
    } catch {
      if (requestId !== this.specificationsRequestId) return;
      this.statusMessage = "Unable to load saved study specifications.";
    } finally {
      if (requestId === this.specificationsRequestId) {
        this.isLoading = false;
      }
    }
  }

  /**
   * Loads the eligible runs for every declared tier of the saved version.
   *
   * The wire call is scoped to one (specification, tier) pair. A reply from a
   * replaced selection cannot overwrite the current runs.
   */
  async loadTierRuns(): Promise<void> {
    const requestId = ++this.tierRunsRequestId;
    const specificationId = this.selectedId;
    const tiers = this.declaredTiers;
    if (
      !this.isSavedVersion ||
      specificationId === null ||
      tiers.length === 0
    ) {
      this.tierRunsByTier = {};
      this.required_inputs = "";
      this.isLoadingRuns = false;
      return;
    }

    this.isLoadingRuns = true;
    try {
      const entries = await Promise.all(
        tiers.map(async (tier) => {
          const reply = await this.api.listStudyTierRuns({
            specification_id: specificationId,
            tier,
            mode: "pilot",
          });
          return [tier, reply.runs, reply.required_inputs ?? ""] as const;
        }),
      );
      if (requestId !== this.tierRunsRequestId) return;
      this.tierRunsByTier = Object.fromEntries(
        entries.map(([tier, runs]) => [tier, runs]),
      );
      this.required_inputs = entries[0]?.[2] ?? "";
    } catch {
      if (requestId !== this.tierRunsRequestId) return;
      this.tierRunsByTier = {};
      this.required_inputs = "";
      this.statusMessage = "Unable to load completed evaluation runs.";
    } finally {
      if (requestId === this.tierRunsRequestId) {
        this.isLoadingRuns = false;
      }
    }
  }

  async selectSpecification(id: string): Promise<void> {
    if (this.isBusy || this.selectedId === id) return;
    const requestId = ++this.selectionRequestId;
    this.resetPreview();
    this.errors = [];
    this.statusMessage = "";
    this.isLoading = true;
    try {
      const reply = await this.api.getStudySpecification(id);
      if (requestId !== this.selectionRequestId) return;
      if (!reply.specification?.content) {
        this.statusMessage = "The selected version is no longer available.";
        return;
      }
      this.applySavedSelection(reply.specification);
    } catch {
      if (requestId !== this.selectionRequestId) return;
      this.statusMessage = "Unable to load the selected study specification.";
    } finally {
      if (requestId === this.selectionRequestId) {
        this.isLoading = false;
      }
    }
  }

  addSpecification(): void {
    if (this.isBusy) return;
    this.selectionRequestId += 1;
    this.resetPreview();
    this.clearSelection();
    this.title = "";
    this.statusMessage = "";
    this.errors = [];
    this.activeTab = "json";
  }

  setTitle(value: string): void {
    if (this.title === value) return;
    this.title = value;
    this.invalidateForEdit();
  }

  setEditorText(value: string): void {
    if (this.editorText === value) return;
    this.editorText = value;
    this.invalidateForEdit();
  }

  async save(): Promise<boolean> {
    if (!this.canSave) return false;
    return this.persist();
  }

  async saveAsNewVersion(): Promise<boolean> {
    if (!this.canSaveAsNewVersion) return false;
    const content = this.validatedContent();
    if (!content) return false;

    const studyId = content.study_id;
    const version = content.specification_version;
    if (typeof studyId !== "string" || !isPositiveInteger(version))
      return false;

    content.specification_version = this.nextVersion(studyId, version);
    this.editorText = JSON.stringify(content, null, 2);
    return this.persist();
  }

  // Save as new version bypasses the Save gate, because the editor always
  // leaves the selected version after it bumps `specification_version`.
  private async persist(): Promise<boolean> {
    const content = this.validatedContent();
    if (!content) return false;

    this.isSaving = true;
    this.errors = [];
    this.statusMessage = "";
    try {
      const reply = await this.api.saveStudySpecification({
        title: this.title.trim(),
        content,
      });
      return await this.applySaveReply(reply);
    } catch {
      this.statusMessage = "Unable to save the study specification.";
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  selectRun(tier: string, runId: string): void {
    if (this.isBusy) return;
    if (this.runUsedByAnotherTier(tier, runId)) {
      this.statusMessage = "This run is already mapped to another tier.";
      return;
    }
    this.selections = { ...this.selections, [tier]: runId };
    this.pickerTier = null;
    this.statusMessage = "";
    this.refreshPreflight();
  }

  clearRun(tier: string): void {
    if (this.isBusy) return;
    const { [tier]: _removed, ...rest } = this.selections;
    this.selections = rest;
    this.refreshPreflight();
  }

  openRunPicker(tier: string): void {
    if (this.isBusy) return;
    this.pickerTier = tier;
  }

  closeRunPicker(): void {
    this.pickerTier = null;
  }

  changeTab(tab: string): void {
    if (tab !== "json" && tab !== "preview" && tab !== "run") return;
    if (this.isBusy) return;
    this.activeTab = tab;
    if (tab === "preview") void this.describePreview();
  }

  async describePreview(): Promise<void> {
    const parsed = this.parsePlainObject(this.editorText);
    const requestId = ++this.previewRequestId;
    if (!parsed) {
      this.isLoadingPreview = false;
      this.previewContent = null;
      this.previewReply = null;
      this.previewNotice = "The study specification is not valid JSON.";
      return;
    }
    this.previewContent = parsed;
    this.previewReply = null;
    this.previewNotice = "";
    this.isLoadingPreview = true;
    try {
      const reply = await this.api.describeStudySpecification(parsed);
      if (requestId !== this.previewRequestId) return;
      this.previewReply = reply;
    } catch {
      if (requestId !== this.previewRequestId) return;
      this.previewReply = null;
      this.previewNotice = "Unable to describe the study specification.";
    } finally {
      if (requestId === this.previewRequestId) {
        this.isLoadingPreview = false;
      }
    }
  }

  refreshPreflight(): void {
    const requestId = ++this.preflightRequestId;
    this.preflightErrors = [];
    if (!this.isSavedVersion || this.selectedId === null) {
      this.preflightStatus = "idle";
      return;
    }
    const tierRuns = this.tierSelections();
    this.preflightStatus = "loading";
    const specificationId = this.selectedId;
    void this.api
      .preflightStudy({
        specification_id: specificationId,
        mode: "pilot",
        tier_runs: tierRuns,
      })
      .then((reply) => this.applyPreflight(requestId, reply))
      .catch(() => this.applyPreflightFailure(requestId));
  }

  async runPilot(): Promise<boolean> {
    if (!this.canStartPilot) return false;
    const locked = this.lockedInputs();
    if (!locked) return false;

    const opened = this.openStudyDocument?.(locked);
    if (!opened) {
      this.statusMessage = "Unable to open the study document.";
      return false;
    }
    if (!opened.created) {
      this.reuseDocument(opened.document);
      return true;
    }

    return this.startPilot(opened.document, locked);
  }

  /**
   * Sends one Pilot start request for a newly created provisional document.
   *
   * The accepted reply must correlate with this exact document, Pilot mode, and
   * attempt identity. A rejected reply rolls only the provisional document
   * back, so no unmatched document becomes visible. An accepted reply without
   * exact correlation, or a rejected request promise, is ambiguous: the start
   * is cancelled for the requested document, and the provisional handle is
   * discarded only after a `closed` or `not_found` acknowledgment. The dialog
   * keeps the locked inputs and shows an actionable error for an in-place retry.
   */
  private async startPilot(
    document: StudyDocument,
    locked: StudyLockedInputs,
  ): Promise<boolean> {
    this.isStarting = true;
    this.errors = [];
    this.statusMessage = "";
    try {
      const reply = await this.api.startStudyAnalysis({
        document_id: document.id,
        mode: "pilot",
        specification_id: locked.specification_id,
        tier_runs: this.tierSelections(),
      });
      const attemptId = this.acceptedPilotAttempt(reply, document);
      if (attemptId !== null) {
        document.markStarted("pilot");
        document.attemptId = attemptId;
        this.activateStudyDocument?.(document);
        this.closeAfterStart();
        return true;
      }
      if (reply.status === "accepted") {
        await this.rejectAmbiguousStart(document);
        return false;
      }
      this.rejectStart(document, reply.errors);
      return false;
    } catch {
      await this.rejectAmbiguousStart(document);
      return false;
    } finally {
      this.isStarting = false;
    }
  }

  /**
   * Confirms one accepted reply against this exact document and Pilot mode.
   *
   * Returns the confirmed attempt identity, or `null` for a rejection or an
   * accepted reply that is missing its attempt identity.
   */
  private acceptedPilotAttempt(
    reply: StartStudyAnalysisReply,
    document: StudyDocument,
  ): string | null {
    if (reply.status !== "accepted") return null;
    if (reply.document_id !== document.id || reply.mode !== "pilot")
      return null;
    const attemptId = reply.attempt_id;
    return typeof attemptId === "string" && attemptId.length > 0
      ? attemptId
      : null;
  }

  /**
   * Cancels an ambiguous start for the originally requested document.
   *
   * A `closed` or `not_found` acknowledgment discards the provisional handle.
   * Any other reply or a transport failure keeps the handle visible with an
   * error, so the user can retry the cancellation by closing it.
   */
  private async rejectAmbiguousStart(document: StudyDocument): Promise<void> {
    const confirmed = await requestStudyClose(this.api, document.id);
    if (confirmed) {
      this.discardStudyDocument?.(document);
      this.statusMessage =
        "The pilot start could not be verified. No analysis is running. Try again.";
      return;
    }
    document.markUnconfirmedStart(
      "pilot",
      "The pilot start could not be verified and the server task could not be cancelled. Close this document to retry cancellation.",
    );
    this.activateStudyDocument?.(document);
    this.statusMessage = "The pilot start could not be verified.";
  }

  /**
   * Activates the document that already holds the identical locked inputs.
   *
   * The dialog closes without another start request, so a running study is
   * never duplicated or discarded.
   */
  private reuseDocument(document: StudyDocument): void {
    this.activateStudyDocument?.(document);
    this.closeAfterStart();
  }

  private closeAfterStart(): void {
    this.open = false;
    this.pickerTier = null;
  }

  /**
   * Removes the newly created provisional document and reports the rejection.
   *
   * The dialog keeps the locked mapping, so the user can correct the setup and
   * start again. A reused document is never rolled back.
   */
  private rejectStart(
    document: StudyDocument,
    errors: readonly StudyRunError[],
  ): void {
    this.rollbackDocument(document, errors);
    this.preflightStatus = "rejected";
    this.preflightErrors = [...errors];
    this.statusMessage = this.startFailureMessage(errors);
  }

  private rollbackDocument(
    document: StudyDocument,
    errors: readonly StudyRunError[],
  ): void {
    if (this.discardStudyDocument) this.discardStudyDocument(document);
    else document.markRejected(errors);
  }

  private startFailureMessage(errors: readonly StudyRunError[]): string {
    const [first] = errors;
    return first
      ? `Pilot analysis rejected: ${formatStudyRunError(first)}`
      : "The pilot analysis was rejected.";
  }

  private applyPreflight(requestId: number, reply: PreflightStudyReply): void {
    if (requestId !== this.preflightRequestId) return;
    this.preflightStatus = reply.status === "ok" ? "ok" : "rejected";
    this.preflightErrors = reply.errors;
  }

  private applyPreflightFailure(requestId: number): void {
    if (requestId !== this.preflightRequestId) return;
    this.preflightStatus = "idle";
    this.preflightErrors = [];
    this.statusMessage = "Unable to check the study bundle.";
  }

  private async applySaveReply(
    reply: SaveStudySpecificationReply,
  ): Promise<boolean> {
    if (reply.status === "ok" && reply.specification) {
      await this.loadSpecifications();
      this.applySavedSelection(reply.specification);
      this.statusMessage = "Study specification saved.";
      return true;
    }
    if (reply.status === "immutable_conflict") {
      const saved = this.selectedSpecification;
      const identity = saved
        ? `${saved.study_id} version ${saved.specification_version}`
        : "This version";
      this.statusMessage = `${identity} is immutable. Use Save as new version.`;
      return false;
    }
    this.errors = reply.errors ?? [];
    if (this.errors.length === 0) {
      this.statusMessage = "Unable to save the study specification.";
    }
    return false;
  }

  private applySavedSelection(specification: StudySpecificationSummary): void {
    const content = specification.content;
    if (!content) return;
    this.selectedId = specification.id;
    this.title = specification.title;
    this.editorText = JSON.stringify(content, null, 2);
    this.savedTitle = specification.title;
    this.savedEditorText = this.editorText;
    this.savedTiers = declaredTierLabels(content);
    this.resetTierMapping();
    this.tierRunsByTier = {};
    void this.loadTierRuns();
    this.refreshPreflight();
  }

  private clearSelection(): void {
    this.selectedId = null;
    this.title = "";
    this.editorText = createDefaultStudySpecification(crypto.randomUUID());
    this.savedTitle = "";
    this.savedEditorText = "";
    this.savedTiers = [];
    this.tierRunsByTier = {};
    this.required_inputs = "";
    this.tierRunsRequestId += 1;
    this.resetTierMapping();
  }

  /**
   * Clears the mapping and preflight once the editor leaves the saved version.
   *
   * The title is immutable saved metadata, so a title edit invalidates the
   * version exactly like a JSON edit. Pilot stays blocked until Save as new
   * version stores a fresh immutable version.
   */
  private invalidateForEdit(): void {
    if (this.selectedId === null) return;
    if (
      this.title === this.savedTitle &&
      this.editorText === this.savedEditorText
    ) {
      return;
    }
    this.resetTierMapping();
  }

  private resetTierMapping(): void {
    this.selections = {};
    this.pickerTier = null;
    this.preflightStatus = "idle";
    this.preflightErrors = [];
    this.preflightRequestId += 1;
    this.statusMessage = "";
  }

  private nextVersion(studyId: string, current: number): number {
    const versions = this.specifications
      .filter((specification) => specification.study_id === studyId)
      .map((specification) => specification.specification_version)
      .filter(isPositiveInteger);
    return Math.max(current, ...versions) + 1;
  }

  private tierSelections(): StudyTierSelection[] {
    return tierSelectionsFrom(this.declaredTiers, this.selections);
  }

  private lockedInputs(): StudyLockedInputs | null {
    const specification = this.selectedSpecification;
    if (!specification) return null;
    return {
      title: specification.title,
      study_id: specification.study_id,
      specification_id: specification.id,
      specification_version: specification.specification_version,
      tiers: this.declaredTiers.map((tier) => this.tierMapping(tier)),
    };
  }

  private tierMapping(tier: string): StudyTierMapping {
    const run = this.runFor(tier);
    return {
      tier,
      run_id: this.selections[tier] ?? "",
      manifest_title: run?.manifest_title ?? null,
      graph_title: run?.graph_title ?? null,
      completed_at: run?.completed_at ?? null,
      plan_count: run?.plan_count ?? 0,
      trial_count: run?.trial_count ?? 0,
    };
  }

  private resetPreview(): void {
    this.previewRequestId += 1;
    this.activeTab = "json";
    this.previewContent = null;
    this.previewReply = null;
    this.previewNotice = "";
    this.isLoadingPreview = false;
  }

  private validatedContent(): Record<string, unknown> | null {
    const parsed = this.parseEditor();
    if (!parsed) return null;
    if (typeof parsed.study_id !== "string" || parsed.study_id.trim() === "") {
      this.errors = [
        { path: "study_id", message: "must be a non-empty string" },
      ];
      return null;
    }
    if (!isPositiveInteger(parsed.specification_version)) {
      this.errors = [
        {
          path: "specification_version",
          message: "must be a positive integer",
        },
      ];
      return null;
    }
    return parsed;
  }

  private parsePlainObject(text: string): Record<string, unknown> | null {
    try {
      const parsed: unknown = JSON.parse(text);
      return typeof parsed === "object" &&
        parsed !== null &&
        !Array.isArray(parsed)
        ? (parsed as Record<string, unknown>)
        : null;
    } catch {
      return null;
    }
  }

  private parseEditor(): Record<string, unknown> | null {
    try {
      const parsed: unknown = JSON.parse(this.editorText);
      if (
        typeof parsed !== "object" ||
        parsed === null ||
        Array.isArray(parsed)
      ) {
        this.errors = [
          { path: "$", message: "study specification must be a JSON object" },
        ];
        return null;
      }
      return parsed as Record<string, unknown>;
    } catch {
      this.errors = [{ path: "$", message: "invalid JSON" }];
      return null;
    }
  }
}

function isPositiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}
