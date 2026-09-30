import type {
  ListStudyTierRunsPayload,
  PreflightStudyReply,
  StudySpecificationSummary,
  StudyTierRunSummary,
} from "../../contracts.generated/dashboard/evaluation";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { DashboardApi } from "../dashboard-api";
import { WorkspaceModel } from "../workspace/WorkspaceModel.svelte";
import { StudyDocument } from "./StudyDocument.svelte";
import { StudyModel } from "./StudyModel.svelte";
import { createDefaultStudySpecification } from "./study-types";

function studyContent(
  studyId = "study-one",
  version = 1,
  tiers: string[] = ["small"],
): Record<string, unknown> {
  const parsed = JSON.parse(createDefaultStudySpecification(studyId));
  parsed.specification_version = version;
  parsed.tiers = tiers;
  return parsed;
}

function specification(
  overrides: Partial<StudySpecificationSummary> = {},
): StudySpecificationSummary {
  return {
    id: "spec-1",
    study_id: "study-one",
    specification_version: 1,
    title: "Study one",
    content: studyContent(),
    ...overrides,
  };
}

function run(id = "run-1"): StudyTierRunSummary {
  return {
    id,
    manifest_id: `manifest-${id}`,
    manifest_title: `Manifest ${id}`,
    graph_title: `Graph ${id}`,
    completed_at: "2026-01-02T03:04:05Z",
    plan_count: 5,
    trial_count: 50,
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

function studyApi() {
  return {
    listStudySpecifications: vi.fn().mockResolvedValue({ specifications: [] }),
    getStudySpecification: vi.fn().mockResolvedValue({ specification: null }),
    saveStudySpecification: vi.fn().mockResolvedValue({
      status: "ok",
      specification: null,
      errors: [],
    }),
    describeStudySpecification: vi.fn().mockResolvedValue({
      status: "ok",
      description: null,
      errors: [],
    }),
    listStudyTierRuns: vi
      .fn()
      .mockResolvedValue({ runs: [run("run-1"), run("run-2")] }),
    preflightStudy: vi.fn().mockResolvedValue({ status: "ok", errors: [] }),
    startStudyAnalysis: vi.fn().mockResolvedValue({
      status: "accepted",
      document_id: "doc-1",
      mode: "pilot",
      attempt_id: "attempt-1",
      errors: [],
    }),
    closeStudyDocument: vi.fn().mockResolvedValue({ status: "closed" }),
  };
}

function modelWith() {
  const api = studyApi();
  const model = new StudyModel(api as unknown as DashboardApi);
  return { api, model };
}

async function settleRuns(model: StudyModel): Promise<void> {
  await vi.waitFor(() => expect(model.isLoadingRuns).toBe(false));
}

async function openSavedVersion(
  api: ReturnType<typeof studyApi>,
  model: StudyModel,
  specificationSummary: StudySpecificationSummary = specification(),
): Promise<void> {
  api.listStudySpecifications.mockResolvedValue({
    specifications: [specificationSummary],
  });
  api.getStudySpecification.mockResolvedValue({
    specification: specificationSummary,
  });
  await model.openDialog();
  await model.selectSpecification(specificationSummary.id);
  await settleRuns(model);
}

function stubDocument() {
  return {
    id: "doc-1",
    attemptId: null as string | null,
    markStarted: vi.fn(),
    markRejected: vi.fn(),
    markUnconfirmedStart: vi.fn(),
  };
}

function asDocument(document: ReturnType<typeof stubDocument>): StudyDocument {
  return document as unknown as StudyDocument;
}

function openedDocument(
  document: ReturnType<typeof stubDocument>,
  created: boolean,
): { document: StudyDocument; created: boolean } {
  return { document: asDocument(document), created };
}

describe("StudyModel", () => {
  beforeEach(() => vi.clearAllMocks());

  it("loads saved versions when the dialog opens", async () => {
    const { api, model } = modelWith();
    api.listStudySpecifications.mockResolvedValue({
      specifications: [specification()],
    });

    await model.openDialog();

    expect(model.open).toBe(true);
    expect(model.specifications).toHaveLength(1);
    expect(model.selectedId).toBeNull();
  });

  it("selects a saved version, declares its tiers, and loads tier runs", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);

    expect(model.selectedId).toBe("spec-1");
    expect(model.title).toBe("Study one");
    expect(model.isSavedVersion).toBe(true);
    expect(model.declaredTiers).toEqual(["small"]);
    expect(model.selections).toEqual({});
    expect(model.tierRunsByTier.small).toHaveLength(2);
  });

  it("scopes each tier-run request to the saved specification and tier", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(
      api,
      model,
      specification({
        content: studyContent("study-one", 1, ["small", "large"]),
      }),
    );

    expect(api.listStudyTierRuns).toHaveBeenCalledWith({
      specification_id: "spec-1",
      tier: "small",
      mode: "pilot",
    });
    expect(api.listStudyTierRuns).toHaveBeenCalledWith({
      specification_id: "spec-1",
      tier: "large",
      mode: "pilot",
    });
    expect(api.listStudyTierRuns).toHaveBeenCalledTimes(2);
  });

  it("saves a new specification with the entered title and content", async () => {
    const { api, model } = modelWith();
    api.saveStudySpecification.mockImplementation(
      async (payload: { title: string; content: Record<string, unknown> }) => ({
        status: "ok",
        specification: specification({
          id: "spec-9",
          title: payload.title,
          study_id: payload.content.study_id as string,
          specification_version: payload.content
            .specification_version as number,
          content: payload.content,
        }),
        errors: [],
      }),
    );
    model.addSpecification();
    model.setTitle("New study");

    const saved = await model.save();

    expect(saved).toBe(true);
    expect(api.saveStudySpecification).toHaveBeenCalledWith({
      title: "New study",
      content: expect.objectContaining({ tiers: ["small"] }),
    });
    expect(model.selectedId).toBe("spec-9");
    expect(model.statusMessage).toBe("Study specification saved.");
  });

  it("rejects invalid JSON before saving", async () => {
    const { api, model } = modelWith();
    model.addSpecification();
    model.setTitle("Broken");
    model.setEditorText("{");

    const saved = await model.save();

    expect(saved).toBe(false);
    expect(api.saveStudySpecification).not.toHaveBeenCalled();
    expect(model.errors).toEqual([{ path: "$", message: "invalid JSON" }]);
  });

  it("disables Save for any edit to a selected saved version, even a manual version bump", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const edited = {
      ...studyContent(),
      study_id: "renamed-study",
      specification_version: 9,
      confidence_level: 0.9,
    };
    model.setEditorText(JSON.stringify(edited, null, 2));

    expect(model.saveWouldConflict).toBe(true);
    expect(model.canSave).toBe(false);
    expect(model.canSaveAsNewVersion).toBe(true);

    const saved = await model.save();

    expect(saved).toBe(false);
    expect(api.saveStudySpecification).not.toHaveBeenCalled();
  });

  it("reports an immutable conflict a Save-as-new-version attempt hits", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    model.setEditorText(`${model.editorText}\n`);
    api.saveStudySpecification.mockResolvedValue({
      status: "immutable_conflict",
      specification: null,
      errors: [],
    });

    const saved = await model.saveAsNewVersion();

    expect(saved).toBe(false);
    expect(model.selectedId).toBe("spec-1");
    expect(model.statusMessage).toContain("immutable");
    expect(model.declaredTiers).toEqual([]);
  });

  it("disables Save for an edited saved version and keeps Save as new version", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);

    expect(model.canSave).toBe(true);
    expect(model.saveWouldConflict).toBe(false);

    model.setEditorText(`${model.editorText}\n`);

    expect(model.saveWouldConflict).toBe(true);
    expect(model.canSave).toBe(false);
    expect(model.canSaveAsNewVersion).toBe(true);
  });

  it("saves an edited version as the next specification version", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const edited = { ...studyContent(), confidence_level: 0.9 };
    model.setEditorText(JSON.stringify(edited, null, 2));
    api.saveStudySpecification.mockImplementation(
      async (payload: { content: Record<string, unknown>; title: string }) => ({
        status: "ok",
        specification: specification({
          id: "spec-2",
          specification_version: payload.content
            .specification_version as number,
          content: payload.content,
        }),
        errors: [],
      }),
    );

    const saved = await model.saveAsNewVersion();

    expect(saved).toBe(true);
    expect(api.saveStudySpecification).toHaveBeenCalledWith(
      expect.objectContaining({
        content: expect.objectContaining({ specification_version: 2 }),
      }),
    );
    expect(model.selectedId).toBe("spec-2");
  });

  it("treats a title edit as an unsaved version and blocks pilot", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    expect(model.canStartPilot).toBe(true);

    model.setTitle("Renamed study");

    expect(model.isSavedVersion).toBe(false);
    expect(model.declaredTiers).toEqual([]);
    expect(model.selections).toEqual({});
    expect(model.preflightStatus).toBe("idle");
    expect(model.canStartPilot).toBe(false);
    expect(model.canSaveAsNewVersion).toBe(true);
  });

  it("keeps pilot disabled until the version, mapping, and preflight agree", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);

    expect(model.canStartPilot).toBe(false);
    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    expect(model.canStartPilot).toBe(true);

    model.setEditorText(model.editorText + "\n");
    expect(model.canStartPilot).toBe(false);
  });

  it("preflights a saved version with an empty mapping", async () => {
    const { api, model } = modelWith();
    api.preflightStudy.mockResolvedValue({
      status: "rejected",
      errors: [{ code: "no_tiers" }],
    });

    await openSavedVersion(api, model);
    await vi.waitFor(() => expect(model.preflightStatus).toBe("rejected"));

    expect(api.preflightStudy).toHaveBeenCalledWith({
      specification_id: "spec-1",
      mode: "pilot",
      tier_runs: [],
    });
    expect(model.preflightErrors).toEqual([{ code: "no_tiers" }]);
    expect(model.missingTiers).toEqual(["small"]);
    expect(model.visiblePreflightErrors).toEqual([]);
  });

  it("keeps partial-mapping row messages specific and retains incompatible runs", async () => {
    const { api, model } = modelWith();
    api.preflightStudy.mockImplementation(
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
    await openSavedVersion(
      api,
      model,
      specification({
        content: studyContent("study-one", 1, ["small", "large"]),
      }),
    );

    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("rejected"));

    expect(model.missingTiers).toEqual(["large"]);
    expect(model.missingSelectionMessage("large")).toBe(
      "Select one completed run for this tier.",
    );
    expect(model.visiblePreflightErrors).toEqual([
      { code: "run_incompatible" },
    ]);
  });

  it("preflights the exact saved version and mapping", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);

    model.selectRun("small", "run-1");

    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    expect(api.preflightStudy).toHaveBeenCalledWith({
      specification_id: "spec-1",
      mode: "pilot",
      tier_runs: [{ tier: "small", run_id: "run-1" }],
    });
    expect(model.missingTiers).toEqual([]);
    expect(model.visiblePreflightErrors).toEqual([]);
  });

  it("ignores a stale preflight reply", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const first = deferred<PreflightStudyReply>();
    const second = deferred<PreflightStudyReply>();
    api.preflightStudy
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise);

    model.selectRun("small", "run-1");
    model.selectRun("small", "run-2");
    second.resolve({ status: "ok", errors: [] });
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    first.resolve({
      status: "rejected",
      errors: [{ code: "tier_declaration_mismatch" }],
    });
    await Promise.resolve();

    expect(model.preflightStatus).toBe("ok");
    expect(model.preflightErrors).toEqual([]);
  });

  it("ignores a stale saved-version list reply", async () => {
    const { api, model } = modelWith();
    const first = deferred<{ specifications: StudySpecificationSummary[] }>();
    api.listStudySpecifications
      .mockReturnValueOnce(first.promise)
      .mockResolvedValueOnce({ specifications: [specification()] });

    void model.openDialog();
    await model.openDialog();
    first.resolve({ specifications: [] });
    await Promise.resolve();

    expect(model.specifications).toHaveLength(1);
    expect(model.specifications[0]?.id).toBe("spec-1");
  });

  it("ignores a stale tier-run reply", async () => {
    const { api, model } = modelWith();
    const first = deferred<{ runs: StudyTierRunSummary[] }>();
    api.listStudyTierRuns.mockReturnValueOnce(first.promise);
    api.listStudySpecifications.mockResolvedValue({
      specifications: [
        specification({ id: "spec-1" }),
        specification({ id: "spec-2" }),
      ],
    });
    api.getStudySpecification.mockImplementation(async (id: string) => ({
      specification: specification({ id }),
    }));
    await model.openDialog();
    await model.selectSpecification("spec-1");

    await model.selectSpecification("spec-2");
    await settleRuns(model);
    expect(model.tierRunsByTier.small).toHaveLength(2);

    first.resolve({ runs: [] });
    await Promise.resolve();

    expect(model.selectedId).toBe("spec-2");
    expect(model.tierRunsByTier.small).toHaveLength(2);
  });

  it("rejects a run already mapped to another tier", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(
      api,
      model,
      specification({
        content: studyContent("study-one", 1, ["small", "large"]),
      }),
    );

    model.selectRun("small", "run-1");
    model.selectRun("large", "run-1");

    expect(model.selections).toEqual({ small: "run-1" });
    expect(model.statusMessage).toBe(
      "This run is already mapped to another tier.",
    );
  });

  it("creates one locked study document, activates it, and starts pilot", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const document = stubDocument();
    const openStudyDocument = vi.fn(() => openedDocument(document, true));
    const activateStudyDocument = vi.fn();
    const discardStudyDocument = vi.fn();
    model.openStudyDocument = openStudyDocument;
    model.activateStudyDocument = activateStudyDocument;
    model.discardStudyDocument = discardStudyDocument;
    api.startStudyAnalysis.mockResolvedValue({
      status: "accepted",
      document_id: "doc-1",
      mode: "pilot",
      attempt_id: "attempt-1",
      errors: [],
    });

    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    const started = await model.runPilot();

    expect(started).toBe(true);
    expect(openStudyDocument).toHaveBeenCalledWith(
      expect.objectContaining({
        study_id: "study-one",
        specification_id: "spec-1",
        specification_version: 1,
        tiers: [expect.objectContaining({ tier: "small", run_id: "run-1" })],
      }),
    );
    expect(api.startStudyAnalysis).toHaveBeenCalledWith({
      document_id: "doc-1",
      mode: "pilot",
      specification_id: "spec-1",
      tier_runs: [{ tier: "small", run_id: "run-1" }],
    });
    expect(document.markStarted).toHaveBeenCalledWith("pilot");
    expect(activateStudyDocument).toHaveBeenCalledWith(document);
    expect(discardStudyDocument).not.toHaveBeenCalled();
    expect(model.open).toBe(false);
  });

  it("removes the provisional document on a rejected start", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const document = stubDocument();
    model.openStudyDocument = () => openedDocument(document, true);
    const activateStudyDocument = vi.fn();
    const discardStudyDocument = vi.fn();
    model.activateStudyDocument = activateStudyDocument;
    model.discardStudyDocument = discardStudyDocument;
    api.startStudyAnalysis.mockResolvedValue({
      status: "rejected",
      document_id: "doc-1",
      mode: "pilot",
      errors: [{ code: "run_incomplete" }],
    });

    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    const started = await model.runPilot();

    expect(started).toBe(false);
    expect(discardStudyDocument).toHaveBeenCalledWith(document);
    expect(activateStudyDocument).not.toHaveBeenCalled();
    expect(document.markStarted).not.toHaveBeenCalled();
    expect(model.statusMessage).toContain("A selected evaluation run");
    expect(model.open).toBe(true);
    expect(model.selectedId).toBe("spec-1");
    expect(model.selections).toEqual({ small: "run-1" });
  });

  it("removes the provisional document on a rejected duplicate start", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const document = stubDocument();
    const activateStudyDocument = vi.fn();
    const discardStudyDocument = vi.fn();
    model.openStudyDocument = () => openedDocument(document, true);
    model.activateStudyDocument = activateStudyDocument;
    model.discardStudyDocument = discardStudyDocument;
    api.startStudyAnalysis.mockResolvedValue({
      status: "rejected",
      document_id: "doc-1",
      mode: "pilot",
      errors: [{ code: "already_running" }],
    });

    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    const started = await model.runPilot();

    expect(started).toBe(false);
    expect(discardStudyDocument).toHaveBeenCalledWith(document);
    expect(activateStudyDocument).not.toHaveBeenCalled();
    expect(document.markStarted).not.toHaveBeenCalled();
    expect(model.statusMessage).toContain("already runs an analysis");
    expect(model.open).toBe(true);
    expect(model.selections).toEqual({ small: "run-1" });
  });

  it("reuses and activates an existing document without another start request", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const document = stubDocument();
    const activateStudyDocument = vi.fn();
    const discardStudyDocument = vi.fn();
    model.openStudyDocument = () => openedDocument(document, false);
    model.activateStudyDocument = activateStudyDocument;
    model.discardStudyDocument = discardStudyDocument;

    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    const started = await model.runPilot();

    expect(started).toBe(true);
    expect(activateStudyDocument).toHaveBeenCalledWith(document);
    expect(api.startStudyAnalysis).not.toHaveBeenCalled();
    expect(document.markStarted).not.toHaveBeenCalled();
    expect(discardStudyDocument).not.toHaveBeenCalled();
    expect(model.open).toBe(false);
  });

  it("rolls back a provisional document on a mismatched document ID", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const document = stubDocument();
    const activateStudyDocument = vi.fn();
    const discardStudyDocument = vi.fn();
    model.openStudyDocument = () => openedDocument(document, true);
    model.activateStudyDocument = activateStudyDocument;
    model.discardStudyDocument = discardStudyDocument;
    api.startStudyAnalysis.mockResolvedValue({
      status: "accepted",
      document_id: "doc-other",
      mode: "pilot",
      attempt_id: "attempt-1",
      errors: [],
    });

    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    const started = await model.runPilot();

    expect(started).toBe(false);
    expect(discardStudyDocument).toHaveBeenCalledWith(document);
    expect(activateStudyDocument).not.toHaveBeenCalled();
    expect(document.markStarted).not.toHaveBeenCalled();
    expect(api.closeStudyDocument).toHaveBeenCalledWith({
      document_id: "doc-1",
    });
    expect(model.statusMessage).toContain("could not be verified");
    expect(model.preflightStatus).toBe("ok");
    expect(model.open).toBe(true);
    expect(model.selections).toEqual({ small: "run-1" });
  });

  it("rolls back a provisional document on a mismatched mode", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const document = stubDocument();
    const activateStudyDocument = vi.fn();
    const discardStudyDocument = vi.fn();
    model.openStudyDocument = () => openedDocument(document, true);
    model.activateStudyDocument = activateStudyDocument;
    model.discardStudyDocument = discardStudyDocument;
    api.startStudyAnalysis.mockResolvedValue({
      status: "accepted",
      document_id: "doc-1",
      mode: "final",
      attempt_id: "attempt-1",
      errors: [],
    });

    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    const started = await model.runPilot();

    expect(started).toBe(false);
    expect(discardStudyDocument).toHaveBeenCalledWith(document);
    expect(activateStudyDocument).not.toHaveBeenCalled();
    expect(document.markStarted).not.toHaveBeenCalled();
    expect(model.statusMessage).toContain("could not be verified");
    expect(model.preflightStatus).toBe("ok");
    expect(model.open).toBe(true);
  });

  it("retains and activates the provisional document when lost-reply cleanup fails", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const document = stubDocument();
    const activateStudyDocument = vi.fn();
    const discardStudyDocument = vi.fn();
    model.openStudyDocument = () => openedDocument(document, true);
    model.activateStudyDocument = activateStudyDocument;
    model.discardStudyDocument = discardStudyDocument;
    api.startStudyAnalysis.mockRejectedValue(new Error("offline"));
    api.closeStudyDocument.mockRejectedValue(new Error("offline"));

    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    const started = await model.runPilot();

    expect(started).toBe(false);
    expect(api.closeStudyDocument).toHaveBeenCalledTimes(1);
    expect(api.closeStudyDocument).toHaveBeenCalledWith({
      document_id: "doc-1",
    });
    expect(discardStudyDocument).not.toHaveBeenCalled();
    expect(document.markUnconfirmedStart).toHaveBeenCalledWith(
      "pilot",
      expect.stringContaining("could not be cancelled"),
    );
    expect(activateStudyDocument).toHaveBeenCalledWith(document);
    expect(model.statusMessage).toContain("could not be verified");
    expect(model.open).toBe(true);
  });

  it("discards the provisional document when lost-reply cleanup succeeds", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const document = stubDocument();
    const activateStudyDocument = vi.fn();
    const discardStudyDocument = vi.fn();
    model.openStudyDocument = () => openedDocument(document, true);
    model.activateStudyDocument = activateStudyDocument;
    model.discardStudyDocument = discardStudyDocument;
    api.startStudyAnalysis.mockRejectedValue(new Error("offline"));

    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));
    const started = await model.runPilot();

    expect(started).toBe(false);
    expect(api.closeStudyDocument).toHaveBeenCalledTimes(1);
    expect(api.closeStudyDocument).toHaveBeenCalledWith({
      document_id: "doc-1",
    });
    expect(discardStudyDocument).toHaveBeenCalledWith(document);
    expect(activateStudyDocument).not.toHaveBeenCalled();
    expect(document.markUnconfirmedStart).not.toHaveBeenCalled();
    expect(model.statusMessage).toContain("could not be verified");
    expect(model.open).toBe(true);
  });

  it("opens the evaluation manifest and closes the dialog", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);
    const onOpenEvaluationManifest = vi.fn();
    model.onOpenEvaluationManifest = onOpenEvaluationManifest;

    model.openEvaluationManifest();

    expect(model.open).toBe(false);
    expect(onOpenEvaluationManifest).toHaveBeenCalledOnce();
  });

  it("filters picker runs that other tiers already use", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(
      api,
      model,
      specification({
        content: studyContent("study-one", 1, ["small", "large"]),
      }),
    );

    model.selectRun("small", "run-1");
    model.openRunPicker("large");

    expect(model.pickerRuns.map((candidate) => candidate.id)).toEqual([
      "run-2",
    ]);
  });

  it("opens and activates one workspace document for identical locked inputs", async () => {
    const api = studyApi();
    const dashboardApi = api as unknown as DashboardApi;
    const workspace = new WorkspaceModel([], [], dashboardApi);
    const model = new StudyModel(dashboardApi);
    model.openStudyDocument = (locked) => workspace.openStudyDocument(locked);
    model.activateStudyDocument = (document) =>
      workspace.activateDocument(document);
    model.discardStudyDocument = (document) =>
      workspace.closeDocument(document.id);
    await openSavedVersion(api, model);
    api.startStudyAnalysis.mockImplementation(
      async (payload: { document_id: string; mode: "pilot" | "final" }) => ({
        status: "accepted",
        document_id: payload.document_id,
        mode: payload.mode,
        attempt_id: "attempt-1",
        errors: [],
      }),
    );
    model.selectRun("small", "run-1");
    await vi.waitFor(() => expect(model.preflightStatus).toBe("ok"));

    const started = await model.runPilot();
    const studyDocuments = () =>
      workspace.documents.filter((document) => document.kind === "study");
    expect(started).toBe(true);
    expect(studyDocuments()).toHaveLength(1);
    expect(workspace.activeDocument?.kind).toBe("study");
    expect(api.startStudyAnalysis).toHaveBeenCalledTimes(1);

    const reopened = await model.runPilot();
    expect(reopened).toBe(true);
    expect(studyDocuments()).toHaveLength(1);
    expect(api.startStudyAnalysis).toHaveBeenCalledTimes(1);
  });

  it("sends the scoped tier-run payload shape", async () => {
    const { api, model } = modelWith();
    await openSavedVersion(api, model);

    const [payload] = api.listStudyTierRuns.mock.calls[0] as [
      ListStudyTierRunsPayload,
    ];
    expect(payload.specification_id).toBe("spec-1");
    expect(payload.tier).toBe("small");
    expect(payload.mode).toBe("pilot");
  });
});
