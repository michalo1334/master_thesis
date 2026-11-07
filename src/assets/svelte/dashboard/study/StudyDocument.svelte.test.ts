import { describe, it, expect, vi } from "vitest";
import { parse } from "yaml";
import { StudyDefinitionModel } from "./StudyDefinitionModel.svelte";
import { StudyDocument } from "./StudyDocument.svelte";
import { WorkspaceModel } from "../workspace/WorkspaceModel.svelte";
import {
  apiFixture,
  definition,
  options,
  reply,
  status,
} from "./test-fixtures";
import { newDraft } from "./types";

describe("Study authoring and workspace", () => {
  it("sends explicit blank fields unchanged for backend validation", () => {
    const model = new StudyDefinitionModel();
    expect(model.draft).toEqual(newDraft());
    expect(model.toWire()).toEqual(newDraft());
    expect(model.error).toBeNull();
    model.draft.revision = "-1.5";
    model.draft.family_alpha = "not a number";
    model.draft.seed = "invalid seed";
    model.draft.tiers[0].budgets = ["", "-4", "9007199254740995"];
    model.draft.candidates = [];
    expect(model.toWire()).toMatchObject({
      revision: "-1.5",
      family_alpha: "not a number",
      seed: "invalid seed",
      tiers: [{ budgets: ["", "-4", "9007199254740995"] }, {}, {}],
      candidates: [],
    });
  });
  it("round-trips an unsafe JavaScript seed through exact YAML and generated wire types", () => {
    const model = new StudyDefinitionModel(definition);
    expect(model.toWire()).toMatchObject({
      revision: "1",
      seed: definition.seed,
      family_alpha: "0.05",
      candidates: [{ id: "tiny", plans: "1", attacks: "2" }],
      tiers: [{ budgets: ["1"] }, {}, {}],
    });
    const yaml = parse(model.yaml, { intAsBigInt: true });
    expect(yaml.seed).toBe(9007199254740993n);
    model.draft.seed = "9007199254740995";
    expect(parse(model.yaml, { intAsBigInt: true }).seed).toBe(
      9007199254740995n,
    );
    expect(model.toWire()?.seed).toBe("9007199254740995");
  });
  it("deduplicates frozen revision tabs and freezes through the shared authoring request", async () => {
    const revision = { study_id: definition.study_id, revision: 1 };
    const api = apiFixture((event) =>
      event === "fetch_study_options"
        ? { options }
        : event === "create_study_revision"
          ? { revision }
          : event === "fetch_study_revision"
            ? {
                detail: {
                  revision,
                  authored: definition,
                  context: {
                    method: "test-method",
                    seed_contract: "test-seeds",
                    measurement_label: "test",
                  },
                  structure: {
                    comparisons: 3,
                    collection_groups: 6,
                    pilot_plans: 1,
                    pilot_attacks: 2,
                  },
                },
              }
            : {},
    );
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.createStudyDraft(definition);
    document.definition.draft.revision = "1";
    await document.freeze();
    expect(document.revision).toEqual(revision);
    expect(workspace.openStudy(revision)).toBe(document);
    expect(workspace.documents).toHaveLength(1);
  });
  it("persists draft fields and views without transient requests, then recovers read-only", async () => {
    const api = apiFixture();
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.createStudyDraft(definition);
    document.definition.draft.revision = "4";
    document.definition.draft.seed = "9007199254740993";
    const saved = document.toPersisted();
    expect(JSON.stringify(saved)).not.toContain("pendingRequest");
    const restored = StudyDocument.fromPersisted(saved, { api, workspace })!;
    expect(restored.definition.draft.seed).toBe("9007199254740993");
    expect(restored.definition.draft.revision).toBe("4");
    expect(
      api.studyRequest.mock.calls.every(
        ([event]) => !event.includes("continue") && !event.includes("start_"),
      ),
    ).toBe(true);
    expect(
      StudyDocument.fromPersisted(
        { ...saved, data: { draft: {} } },
        { api, workspace },
      ),
    ).toBeUndefined();
  });
  it("recovers result sections, filters and display units without restoring approval consent", async () => {
    const api = apiFixture();
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.openStudy({ study_id: "a", revision: 1 });
    document.selectExecution("execution-1");
    document.tab = "executions";
    const model = document.selectedExecution!;
    model.view = "results";
    model.presentation.resultTab = "timing";
    model.presentation.timingTier = "large";
    model.presentation.unit = "ms";
    model.overrideConfirmed = true;
    const saved = document.toPersisted();
    const restored = StudyDocument.fromPersisted(saved, { api, workspace })!;
    expect(restored.selectedExecution).toBeUndefined();
    restored.recover({ api, workspace });
    expect(restored.selectedExecution?.view).toBe("results");
    expect(restored.selectedExecution?.presentation.resultTab).toBe("timing");
    expect(restored.selectedExecution?.presentation.timingTier).toBe("large");
    expect(restored.selectedExecution?.presentation.unit).toBe("ms");
    expect(restored.selectedExecution?.overrideConfirmed).toBe(false);
  });

  it("restores a lazy stub and preserves its payload until activation", async () => {
    const api = apiFixture();
    const workspace = new WorkspaceModel([], [], api);
    const saved = new StudyDocument({
      study_id: "saved",
      revision: 1,
    }).toPersisted();
    saved.data = {
      tab: "executions",
      selectedExecutionId: "execution-1",
      view: "results",
      presentation: { resultTab: "timing", unit: "ms" },
    };
    const restored = StudyDocument.fromPersisted(saved, { api, workspace })!;
    expect(api.studyRequest).not.toHaveBeenCalled();
    expect(restored.needsRecovery()).toBe(true);
    expect(restored.toPersisted()).toEqual(saved);
    expect(restored.executionModels).toEqual([]);
    workspace.documents = [restored];
    workspace.selectDocument(restored.id);
    expect(restored.needsRecovery()).toBe(false);
    expect(restored.selectedExecution?.view).toBe("results");
    expect(restored.selectedExecution?.presentation.unit).toBe("ms");
    await vi.waitFor(() =>
      expect(api.studyRequest).toHaveBeenCalledWith("fetch_study_status", {
        execution_id: "execution-1",
      }),
    );
    expect(
      api.studyRequest.mock.calls.some(
        ([event]) =>
          event === "start_study_execution" ||
          event === "continue_study_execution",
      ),
    ).toBe(false);
  });

  it("keeps unactivated Study tabs through repeated workspace snapshots", () => {
    const api = apiFixture();
    const workspace = new WorkspaceModel([], [], api);
    workspace.openRuns();
    const saved = new StudyDocument({
      study_id: "background",
      revision: 2,
    }).toPersisted();
    saved.data = {
      tab: "executions",
      selectedExecutionId: "execution-1",
      view: "results",
      presentation: { unit: "ms" },
    };
    const envelope = workspace.toPersistence()!;
    envelope.documents.push(saved);
    const restored = new WorkspaceModel([], [], api);
    restored.restorePersistence(envelope);
    const stub = restored.documents.find(
      (document) => document.kind === "study",
    )!;
    expect(stub.needsRecovery()).toBe(true);
    expect(stub.toPersisted()).toEqual(saved);
    const again = new WorkspaceModel([], [], api);
    again.restorePersistence(restored.toPersistence());
    expect(again.documents.some((document) => document.kind === "study")).toBe(
      true,
    );
    expect(api.studyRequest).not.toHaveBeenCalled();
  });

  it.each([
    [
      "wrong kind",
      (saved: any) => {
        saved.kind = "graph";
      },
    ],
    [
      "missing title",
      (saved: any) => {
        delete saved.title;
      },
    ],
    [
      "missing document ID",
      (saved: any) => {
        delete saved.ids.document_id;
      },
    ],
    [
      "invalid frozen identity",
      (saved: any) => {
        saved.ids.study_id = "a";
        saved.ids.revision = "invalid";
      },
    ],
    [
      "null state",
      (saved: any) => {
        saved.data = null;
      },
    ],
    [
      "array state",
      (saved: any) => {
        saved.data = [];
      },
    ],
    [
      "null tier",
      (saved: any) => {
        saved.data.draft.tiers[0] = null;
      },
    ],
    [
      "null alternative",
      (saved: any) => {
        saved.data.draft.tiers[0].alternatives = [null];
      },
    ],
    [
      "null candidate",
      (saved: any) => {
        saved.data.draft.candidates = [null];
      },
    ],
    [
      "non-string rule",
      (saved: any) => {
        saved.data.draft.rules = [null];
      },
    ],
    [
      "invalid selected execution",
      (saved: any) => {
        saved.data.selectedExecutionId = {};
      },
    ],
  ])("skips malformed persisted Study data: %s", (_name, corrupt) => {
    const api = apiFixture();
    const workspace = new WorkspaceModel([], [], api);
    const saved = new StudyDocument().toPersisted();
    corrupt(saved);
    expect(
      StudyDocument.fromPersisted(saved, { api, workspace }),
    ).toBeUndefined();
    expect(api.studyRequest).not.toHaveBeenCalled();
  });

  it("clones declared settings and requires a new confirmed revision identity", () => {
    const workspace = new WorkspaceModel([], [], apiFixture());
    const document = workspace.createStudyDraft(definition);
    expect(document.definition.draft.revision).toBe("");
    expect(document.definition.draft.seed).toBe(definition.seed);
  });
  it("clears attention for a reviewed completion and keeps background execution attention", async () => {
    const api = apiFixture();
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.openStudy({ study_id: "a", revision: 1 });
    document.tab = "executions";
    document.selectExecution("execution-1");
    await vi.waitFor(() =>
      expect(document.selectedExecution?.status).not.toBeNull(),
    );
    const model = document.selectedExecution!;
    model.pendingRequestId = "request";
    document.finished({
      document_id: document.id,
      execution_id: "execution-1",
      request_id: "request",
      status: status("succeeded"),
    });
    expect(model.attention).toBe(false);
    model.attention = true;
    document.tab = "definition";
    document.markRead();
    expect(model.attention).toBe(true);
    document.tab = "executions";
    document.markRead();
    expect(model.attention).toBe(false);
  });

  it("requires history reconciliation after an uncertain Start and never retries Start automatically", async () => {
    const api = apiFixture(async (event) => {
      if (event === "start_study_execution") throw new Error("lost");
      return {};
    });
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.openStudy({ study_id: "a", revision: 1 });
    await document.start();
    await document.start();
    expect(
      api.studyRequest.mock.calls.filter(
        ([event]) => event === "start_study_execution",
      ),
    ).toHaveLength(1);
    expect(document.startUncertain).toBe(true);
    await document.refreshExecutions();
    expect(document.startUncertain).toBe(false);
  });
  it("rejects delayed history after document closure before creating any observer", async () => {
    let release!: (value: any) => void;
    const api = apiFixture((event) =>
      event === "fetch_study_executions"
        ? new Promise((resolve) => (release = resolve))
        : event === "fetch_study_status"
          ? { execution: status() }
          : {},
    );
    const workspace = new WorkspaceModel([], [], api);
    const document = new StudyDocument({ study_id: "a", revision: 1 });
    document.attach({ api, workspace });
    const request = document.refreshExecutions();
    document.dispose();
    release({
      executions: [
        {
          ...status(),
          started_at: "2026-01-01T00:00:00Z",
          updated_at: "2026-01-01T00:00:00Z",
        },
      ],
      total: 1,
    });
    await request;
    expect(document.executionModels).toHaveLength(0);
    expect(
      api.studyRequest.mock.calls.some(
        ([name]) => name === "watch_study_execution",
      ),
    ).toBe(false);
  });

  it("warns before discarding a draft and releases document-owned requests on close", () => {
    const api = apiFixture();
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.createStudyDraft();
    const confirm = vi.spyOn(globalThis, "confirm").mockReturnValue(false);
    workspace.closeDocument(document.id);
    expect(workspace.documents).toContain(document);
    confirm.mockReturnValue(true);
    workspace.closeDocument(document.id);
    expect(api.studyRequest).toHaveBeenCalledWith("close_study_document", {
      document_id: document.id,
    });
    confirm.mockRestore();
  });
});
