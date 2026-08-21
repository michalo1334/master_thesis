import { beforeEach, describe, expect, it, vi } from "vitest";
import { ManifestModel } from "./ManifestModel.svelte";
import type { DashboardApi } from "../dashboard-api";

function api(): DashboardApi {
  return {
    openGraph: vi.fn(),
    saveGraph: vi.fn(),
    runSimulation: vi.fn(),
    runOptimization: vi.fn(),
    runWorkflow: vi.fn(),
    requestSimulationReport: vi.fn(),
    requestOptimizationReport: vi.fn(),
    fetchExperiments: vi.fn(),
    fetchOptimizationRuns: vi.fn(),
    fetchRuns: vi.fn(),
    fetchGraphConnectivity: vi.fn(),
    fetchGraphProjection: vi.fn(),
    fetchDocumentCatalog: vi.fn(),
    createNodeDraft: vi.fn(),
    createConnectionDraft: vi.fn(),
    compareGraphs: vi.fn(),
    setGraphRevisionFavorite: vi.fn(),
    createFolder: vi.fn(),
    deleteFolder: vi.fn(),
    moveGraphToFolder: vi.fn(),
    fetchAnalyses: vi.fn(),
    setGraphAnalyses: vi.fn(),
    setReportAnalysis: vi.fn(),
    listManifests: vi.fn().mockResolvedValue({ manifests: [] }),
    getManifest: vi.fn(),
    saveManifest: vi.fn(),
    startEvaluation: vi.fn(),
    requestEvaluationReport: vi.fn(),
  } as DashboardApi;
}

const validContent = {
  schema_version: 1,
  model_version: "current-model-version",
  id: "fixed-enterprise-v1",
  source: { type: "topology", generator: "enterprise", hosts: 50, seed: 42 },
  attacker: {
    entry_host: { type: "semantic_key", value: "internet" },
    max_attempts: 1,
  },
  model: {
    objective: "mission_then_blast_radius",
    require_pre_attack_feasibility: true,
  },
  budgets: [1, 2, 3],
  strategies: ["null", "cvss"],
  selection_seeds: [101, 102],
  evaluation: { trials: 1000, seed: 9001 },
};

describe("ManifestModel", () => {
  let model: ManifestModel;
  let dashboardApi: DashboardApi;

  beforeEach(() => {
    dashboardApi = api();
    model = new ManifestModel(dashboardApi);
  });

  it("loads saved manifests on open", async () => {
    vi.mocked(dashboardApi.listManifests).mockResolvedValue({
      manifests: [{ id: "m1", manifest_id: "fixed-enterprise-v1", title: "T" }],
    });

    await model.openDialog();

    expect(model.open).toBe(true);
    expect(model.manifests).toHaveLength(1);
  });

  it("selects a manifest and loads its content", async () => {
    vi.mocked(dashboardApi.getManifest).mockResolvedValue({
      manifest: {
        id: "m1",
        manifest_id: "fixed-enterprise-v1",
        title: "T",
        content: validContent,
      },
    });

    await model.selectManifest("m1");

    expect(model.selectedId).toBe("m1");
    expect(model.title).toBe("T");
    expect(JSON.parse(model.editorText)).toEqual(validContent);
  });

  it("gives each new manifest a fresh id", () => {
    model.addManifest();

    const firstId = JSON.parse(model.editorText).id;

    model.addManifest();

    const secondId = JSON.parse(model.editorText).id;

    expect(firstId).not.toBe("fixed-enterprise-v1");
    expect(secondId).not.toBe(firstId);
  });

  it("rejects a duplicate id when creating a manifest", async () => {
    model.manifests = [
      { id: "m1", manifest_id: "existing-id", title: "Existing" },
    ];
    model.addManifest();
    model.title = "T";
    model.editorText = JSON.stringify({ ...validContent, id: "existing-id" });

    const ok = await model.save();

    expect(ok).toBe(false);
    expect(model.errors).toEqual([{ path: "id", message: "already exists" }]);
    expect(dashboardApi.saveManifest).not.toHaveBeenCalled();
  });

  it("saves a manifest and refreshes the list", async () => {
    model.title = "T";
    model.editorText = JSON.stringify(validContent, null, 2);
    vi.mocked(dashboardApi.saveManifest).mockResolvedValue({
      status: "ok",
      manifest: {
        id: "m1",
        manifest_id: "fixed-enterprise-v1",
        title: "T",
        content: validContent,
      },
      errors: [],
    });

    const ok = await model.save();

    expect(ok).toBe(true);
    expect(dashboardApi.saveManifest).toHaveBeenCalledWith({
      manifest_id: "fixed-enterprise-v1",
      title: "T",
      content: validContent,
    });
    expect(model.statusMessage).toBe("Manifest saved.");
  });

  it("saves an edited manifest with its existing id", async () => {
    model.manifests = [
      { id: "m1", manifest_id: "fixed-enterprise-v1", title: "Old" },
    ];
    model.selectedId = "m1";
    model.title = "T";
    model.editorText = JSON.stringify(validContent, null, 2);
    vi.mocked(dashboardApi.saveManifest).mockResolvedValue({
      status: "ok",
      manifest: {
        id: "m1",
        manifest_id: "fixed-enterprise-v1",
        title: "T",
        content: validContent,
      },
      errors: [],
    });

    const ok = await model.save();

    expect(ok).toBe(true);
    expect(dashboardApi.saveManifest).toHaveBeenCalledWith({
      manifest_id: "fixed-enterprise-v1",
      title: "T",
      content: validContent,
    });
  });

  it("surfaces validation errors from the backend", async () => {
    model.title = "T";
    model.editorText = JSON.stringify(
      { ...validContent, budgets: [] },
      null,
      2,
    );
    vi.mocked(dashboardApi.saveManifest).mockResolvedValue({
      status: "invalid_manifest",
      manifest: null,
      errors: [{ path: "budgets", message: "must not be empty" }],
    });

    const ok = await model.save();

    expect(ok).toBe(false);
    expect(model.errors).toEqual([
      { path: "budgets", message: "must not be empty" },
    ]);
  });

  it("rejects invalid JSON in the editor", async () => {
    model.title = "T";
    model.editorText = "{not json";

    const ok = await model.save();

    expect(ok).toBe(false);
    expect(model.errors).toEqual([{ path: "$", message: "invalid JSON" }]);
    expect(dashboardApi.saveManifest).not.toHaveBeenCalled();
  });

  it("starts an evaluation for the selected manifest", async () => {
    model.manifests = [
      { id: "m1", manifest_id: "fixed-enterprise-v1", title: "T" },
    ];
    model.selectedId = "m1";
    vi.mocked(dashboardApi.startEvaluation).mockResolvedValue({
      status: "accepted",
      run_id: "run-1",
      errors: [],
    });

    const ok = await model.start();

    expect(ok).toBe(true);
    expect(dashboardApi.startEvaluation).toHaveBeenCalledWith(
      "fixed-enterprise-v1",
    );
    expect(model.statusMessage).toBe("Evaluation started.");
  });

  it("requires saving changes before starting an evaluation", async () => {
    vi.mocked(dashboardApi.getManifest).mockResolvedValue({
      manifest: {
        id: "m1",
        manifest_id: "fixed-enterprise-v1",
        title: "T",
        content: validContent,
      },
    });
    model.manifests = [
      { id: "m1", manifest_id: "fixed-enterprise-v1", title: "T" },
    ];

    await model.selectManifest("m1");
    model.editorText = JSON.stringify({ ...validContent, budgets: [1] });

    expect(model.canStart).toBe(false);
    await expect(model.start()).resolves.toBe(false);
    expect(dashboardApi.startEvaluation).not.toHaveBeenCalled();
  });
});
