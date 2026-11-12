import { studyLifecycle } from "../../contracts.generated/dashboard/study";
import type {
  ContinueFinished,
  ExecutionEvent,
  ExecutionSummary,
  Revision,
  RevisionDetail,
  Status,
} from "../../contracts.generated/dashboard/study";
import { WorkspaceDocumentBase } from "../workspace/WorkspaceDocument.svelte";
import type { DashboardRecoveryContext } from "../workspace/recovery-context";
import {
  isPersistedDocumentOfKind,
  type PersistedWorkspaceDocument,
} from "../../ui-kit/workspace/workspace-persistence";
import type { DashboardApi } from "../dashboard-api";
import { StudyDefinitionModel } from "./StudyDefinitionModel.svelte";
import { StudyExecutionModel } from "./StudyExecutionModel.svelte";
import { isStudyDraft, type StudyDraft } from "./types";

export class StudyDocument extends WorkspaceDocumentBase {
  readonly kind = "study" as const;
  readonly icon = "beaker";
  readonly documentLabel = "Study";
  readonly id: string;
  static readonly createOption = {
    id: "study",
    label: "Study",
    icon: "beaker",
  };
  revision = $state.raw<Revision | null>(null);
  detail = $state.raw<RevisionDetail | null>(null);
  definition = new StudyDefinitionModel();
  executions = $state.raw<ExecutionSummary[]>([]);
  executionModels = $state.raw<StudyExecutionModel[]>([]);
  executionTotal = $state(0);
  executionPage = $state(1);
  selectedExecutionId = $state<string | null>(null);
  tab = $state<"definition" | "executions">("definition");
  loading = $state(false);
  starting = $state(false);
  startUncertain = $state(false);
  message = $state("");
  selectedRow = $derived.by(() => {
    const execution = this.selectedExecution;
    return this.tab === "executions" &&
      execution?.view === "results" &&
      execution.presentation.resultTab === "comparisons"
      ? (execution.selectedComparison ?? null)
      : null;
  });
  private api?: DashboardApi;
  private disposed = false;
  private historyGeneration = 0;
  private loaded = false;
  private workspace?: DashboardRecoveryContext["workspace"];

  constructor(revision?: Revision, id: string = crypto.randomUUID()) {
    super();
    this.id = id;
    if (revision) this.revision = revision;
  }
  get graphSummaries() {
    return this.workspace?.graphSummaries ?? [];
  }
  openGraph(id: string): void {
    if (this.workspace && this.api)
      void this.workspace.openGraphRevision(this.api, id);
  }

  get title(): string {
    const name = (
      this.detail?.authored.name ?? this.definition.draft.name
    ).trim();
    if (this.persistedData) return (this.persistedData as PersistedStudy).title;
    return this.revision
      ? `Study: ${name || this.revision.study_id} r${this.revision.revision}`
      : `Study draft${name ? ": " + name : ""}`;
  }
  get hasAttention(): boolean {
    return this.executionModels.some((model) => model.attention);
  }
  get selectedExecution(): StudyExecutionModel | undefined {
    return this.executionModels.find(
      (model) => model.executionId === this.selectedExecutionId,
    );
  }
  get isDraft(): boolean {
    return this.revision === null;
  }

  attach(context: DashboardRecoveryContext): void {
    this.api = context.api;
    this.workspace = context.workspace;
  }
  needsRecovery(): boolean {
    return !this.loaded;
  }
  recover(context: DashboardRecoveryContext): void {
    if (this.disposed) return;
    this.attach(context);
    const saved = this.persistedData as PersistedStudy | undefined;
    if (saved) {
      const state = saved.data;
      this.tab = state?.tab === "executions" ? "executions" : "definition";
      if (typeof state?.selectedExecutionId === "string") {
        this.selectedExecutionId = state.selectedExecutionId;
        const model = this.execution(state.selectedExecutionId);
        model.restorePresentation(state.presentation);
        model.view =
          state.view === "pilot" || state.view === "results"
            ? state.view
            : "status";
      }
      this.persistedData = undefined;
    }
    void this.load();
  }

  async load(): Promise<void> {
    if (!this.api || this.loading || this.disposed) return;
    this.loading = true;
    this.loaded = true;
    try {
      const options = await this.api.studyRequest("fetch_study_options", {
        document_id: this.id,
      });
      if (this.disposed) return;
      this.definition.options = options.options ?? null;
      this.definition.error = options.error ?? null;
      if (!this.revision && options.options) {
        this.definition.draft.study_id ||= options.options.study_id ?? "";
        this.definition.draft.family_id ||= options.options.family_id ?? "";
      }
      if (this.revision) {
        const reply = await this.api.studyRequest("fetch_study_revision", {
          revision: this.revision,
        });
        if (this.disposed) return;
        if (reply.detail) this.detail = reply.detail;
        else this.definition.error = reply.error ?? null;
        await this.refreshExecutions();
      }
    } catch {
      this.message = "Could not load the study. Use Refresh.";
    } finally {
      this.loading = false;
    }
  }

  async freeze(): Promise<void> {
    if (this.disposed || !this.api || this.revision || this.definition.freezing)
      return;
    const definition = this.definition.toWire();
    this.definition.freezing = true;
    this.definition.error = null;
    try {
      const reply = await this.api.studyRequest("create_study_revision", {
        definition,
      });
      if (this.disposed) return;
      if (reply.revision) {
        this.revision = reply.revision;
        this.message = "Revision frozen.";
        this.workspace?.studyFrozen(this);
        await this.load();
      } else this.definition.error = reply.error ?? null;
    } catch {
      this.message =
        "The freeze reply was lost. Open saved revisions to check the declared identity.";
    } finally {
      this.definition.freezing = false;
    }
  }

  async refreshExecutions(page = this.executionPage): Promise<void> {
    if (!this.api || !this.revision || this.disposed) return;
    const generation = ++this.historyGeneration;
    try {
      const reply = await this.api.studyRequest("fetch_study_executions", {
        revision: this.revision,
        limit: 5,
        offset: (page - 1) * 5,
      });
      if (this.disposed || generation !== this.historyGeneration) return;
      if (reply.status !== "ok") {
        this.definition.error = reply.error ?? null;
        return;
      }
      this.executions = reply.executions;
      this.executionTotal = reply.total ?? reply.executions.length;
      this.executionPage = page;
      for (const summary of reply.executions) {
        this.execution(summary.execution_id, summary);
      }
      if (!this.selectedExecutionId)
        this.selectedExecutionId = reply.executions[0]?.execution_id ?? null;
      if (
        this.selectedExecutionId &&
        !this.executionModels.some(
          (m) => m.executionId === this.selectedExecutionId,
        )
      )
        this.execution(this.selectedExecutionId);
      this.startUncertain = false;
    } catch {
      if (this.disposed || generation !== this.historyGeneration) return;
      this.message =
        "Could not reconcile execution history. Start remains disabled if its previous reply is uncertain.";
    }
  }

  private execution(id: string, status?: Status): StudyExecutionModel {
    const existing = this.executionModels.find(
      (model) => model.executionId === id,
    );
    if (existing) return existing;
    const model = new StudyExecutionModel(id, this.id, this.api!, status);
    this.executionModels = [...this.executionModels, model];
    void model.refresh();
    return model;
  }

  selectExecution(id: string): void {
    if (this.disposed) return;
    this.selectedExecutionId = id;
    const model = this.execution(id);
    model.attention = false;
    void model.refresh();
  }
  markRead(): void {
    if (this.tab === "executions" && this.selectedExecution)
      this.selectedExecution.attention = false;
  }

  async start(): Promise<void> {
    if (
      this.disposed ||
      !this.api ||
      !this.revision ||
      this.starting ||
      this.startUncertain
    )
      return;
    this.starting = true;
    this.message = "Starting a new Pilot execution…";
    try {
      const reply = await this.api.studyRequest("start_study_execution", {
        revision: this.revision,
        document_id: this.id,
      });
      if (this.disposed) return;
      if (reply.execution) {
        this.execution(reply.execution.execution_id, reply.execution);
        this.selectedExecutionId = reply.execution.execution_id;
        this.tab = "executions";
        this.message = "Pilot started. Continue advances this execution.";
        await this.refreshExecutions(1);
      } else {
        this.definition.error = reply.error ?? null;
        this.message = "Pilot start was rejected.";
      }
    } catch {
      this.startUncertain = true;
      this.message =
        "The Start reply was lost. Refresh execution history and inspect it before starting another execution.";
    } finally {
      this.starting = false;
    }
    if (this.workspace) this.workspace.statusMessage = this.message;
  }

  clone(): void {
    if (this.detail && this.workspace)
      this.workspace.createStudyDraft(this.detail.authored);
  }

  observed(event: ExecutionEvent, active: boolean): void {
    const model = this.executionModels.find(
      (model) => model.executionId === event.execution_id,
    );
    const reviewed =
      active &&
      this.tab === "executions" &&
      this.selectedExecutionId === event.execution_id;
    const previous = model?.status?.state;
    if (model?.observed(event, reviewed)) {
      this.executions = this.executions.map((entry) =>
        entry.execution_id === event.execution_id
          ? {
              ...entry,
              state: event.status.state,
              pilot_outcome: event.status.pilot_outcome,
              selection: event.status.selection,
            }
          : entry,
      );
      if (
        this.workspace &&
        previous &&
        previous !== event.status.state &&
        studyLifecycle[event.status.state].attention
      )
        this.workspace.statusMessage = `${this.title}: ${event.status.state.replaceAll("_", " ")}.`;
    }
  }
  finished(event: ContinueFinished): void {
    const model = this.executionModels.find(
      (model) => model.executionId === event.execution_id,
    );
    const matched = model?.pendingRequestId === event.request_id;
    model?.finished(event);
    if (
      model &&
      this.workspace?.selectedDocumentId === this.id &&
      this.tab === "executions" &&
      this.selectedExecutionId === event.execution_id
    )
      model.attention = false;
    if (matched && this.workspace) {
      this.message = event.status
        ? `Execution ${event.status.state.replaceAll("_", " ")}.`
        : "Continue returned with an error. Refresh accepted status.";
      this.workspace.statusMessage = `${this.title}: ${this.message}`;
    }
  }
  reconnect(): void {
    this.starting = false;
    for (const model of this.executionModels) model.reconnect();
    void this.refreshExecutions();
  }
  dispose(): void {
    this.disposed = true;
    this.historyGeneration++;
    for (const model of this.executionModels) model.dispose();
    void this.api
      ?.studyRequest("close_study_document", { document_id: this.id })
      .catch(() => {});
  }

  toPersisted(): PersistedStudy {
    if (this.persistedData !== undefined)
      return this.persistedData as PersistedStudy;
    return {
      kind: this.kind,
      ids: {
        document_id: this.id,
        ...(this.revision
          ? {
              study_id: this.revision.study_id,
              revision: String(this.revision.revision),
            }
          : {}),
      },
      title: this.title,
      data: {
        ...(this.revision
          ? {}
          : { draft: $state.snapshot(this.definition.draft) }),
        tab: this.tab,
        selectedExecutionId: this.selectedExecutionId,
        view: this.selectedExecution?.view ?? "status",
        presentation: this.selectedExecution
          ? $state.snapshot(this.selectedExecution.presentation)
          : undefined,
      },
    };
  }

  static fromPersisted(
    data: unknown,
    _context: DashboardRecoveryContext,
  ): StudyDocument | undefined {
    if (!isStudyPersisted(data)) return;
    const identity =
      typeof data.ids.study_id === "string"
        ? { study_id: data.ids.study_id, revision: Number(data.ids.revision) }
        : undefined;
    const document = new StudyDocument(identity, data.ids.document_id);
    if (!identity && data.data?.draft)
      document.definition.draft = {
        ...structuredClone(data.data.draft),
        name: data.data.draft.name ?? "",
      };
    document.setPersisted(data);
    return document;
  }
}

type PersistedStudy = PersistedWorkspaceDocument & {
  kind: "study";
  ids: { document_id: string; study_id?: string; revision?: string };
  data?: {
    draft?: StudyDraft;
    tab?: string;
    selectedExecutionId?: string | null;
    view?: string;
    presentation?: unknown;
  };
};

function isStudyPersisted(value: unknown): value is PersistedStudy {
  if (
    !isPersistedDocumentOfKind<{ document_id: string }>(value, "study", [
      "document_id",
    ])
  )
    return false;
  const saved = value as PersistedStudy;
  if (
    saved.data !== undefined &&
    (!saved.data || typeof saved.data !== "object" || Array.isArray(saved.data))
  )
    return false;
  const state = saved.data;
  if (state?.draft !== undefined && !isStudyDraft(state.draft)) return false;
  if (state?.tab !== undefined && typeof state.tab !== "string") return false;
  if (state?.view !== undefined && typeof state.view !== "string") return false;
  if (
    state?.selectedExecutionId != null &&
    typeof state.selectedExecutionId !== "string"
  )
    return false;
  if (saved.ids.study_id !== undefined || saved.ids.revision !== undefined)
    return (
      typeof saved.ids.study_id === "string" &&
      typeof saved.ids.revision === "string" &&
      /^\d+$/.test(saved.ids.revision)
    );
  return isStudyDraft(state?.draft);
}
