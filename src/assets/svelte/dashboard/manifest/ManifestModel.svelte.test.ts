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
    requestEvaluationAnalysis: vi.fn(),
    cancelRun: vi.fn(),
  } as DashboardApi;
}

const validContent = {
  schema_version: 3,
  model_version: "current-model-version",
  id: "fixed-enterprise-v1",
  source: { type: "topology", generator: "enterprise", hosts: 50, seed: 42 },
  attacker: {
    entry_host: { type: "semantic_key", value: "internet" },
    max_attempts: 1,
  },
  model_variants: [
    {
      id: "full",
      objective: "mission_then_blast_radius",
      require_pre_attack_feasibility: true,
    },
    {
      id: "blast_only",
      objective: "blast_radius_only",
      require_pre_attack_feasibility: true,
    },
    {
      id: "full_unconstrained",
      objective: "mission_then_blast_radius",
      require_pre_attack_feasibility: false,
    },
  ],
  strategy_runs: [
    {
      model_variant: "full",
      strategy: "cvss",
      budget: 1,
      selection_seeds: [101],
    },
    {
      model_variant: "full",
      strategy: "simulation_informed",
      budget: 1,
      selection_seeds: [201, 202],
    },
    {
      model_variant: "blast_only",
      strategy: "simulation_informed",
      budget: 1,
      selection_seeds: [201, 202],
    },
    {
      model_variant: "full_unconstrained",
      strategy: "simulation_informed",
      budget: 1,
      selection_seeds: [201, 202],
    },
  ],
  analysis: {
    primary_comparisons: [
      {
        strategy: "simulation_informed",
        model_variant: "full",
        baseline: "cvss",
        baseline_model_variant: "full",
        budget: 1,
        outcome: "blast_radius",
      },
      {
        strategy: "simulation_informed",
        model_variant: "blast_only",
        baseline: "simulation_informed",
        baseline_model_variant: "full",
        budget: 1,
        outcome: "blast_radius",
      },
      {
        strategy: "simulation_informed",
        model_variant: "full_unconstrained",
        baseline: "simulation_informed",
        baseline_model_variant: "full",
        budget: 1,
        outcome: "blast_radius",
      },
    ],
    confidence_level: 0.95,
    bootstrap_resamples: 100,
    permutation_resamples: 100,
    multiplicity_correction: "holm",
    seed: 9001,
    pilot: { ci_half_width: 0.25 },
  },
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

  it.each([
    ["missing", undefined],
    ["null", null],
    ["primitive", "not-an-object"],
    ["array", ["not-an-object"]],
  ])(
    "rejects %s manifest content without changing selection state",
    async (_label, content) => {
      vi.mocked(dashboardApi.getManifest).mockResolvedValue({
        manifest: {
          id: "m1",
          manifest_id: "fixed-enterprise-v1",
          title: "T",
          content: validContent,
        },
      });
      await model.selectManifest("m1");
      model.editorText = `${model.editorText}\n`;
      const previousState = {
        selectedId: model.selectedId,
        title: model.title,
        editorText: model.editorText,
        hasUnsavedChanges: model.hasUnsavedChanges,
      };

      vi.mocked(dashboardApi.getManifest).mockResolvedValue({
        manifest: {
          id: "m2",
          manifest_id: "other-manifest",
          title: "Other",
          content: content as never,
        },
      });

      await model.selectManifest("m2");

      expect(model.statusMessage).toBe("Unable to load the selected manifest.");
      expect({
        selectedId: model.selectedId,
        title: model.title,
        editorText: model.editorText,
        hasUnsavedChanges: model.hasUnsavedChanges,
      }).toEqual(previousState);
    },
  );

  it("gives each new manifest a fresh id", () => {
    model.addManifest();

    const firstId = JSON.parse(model.editorText).id;

    model.addManifest();

    const secondId = JSON.parse(model.editorText).id;

    expect(firstId).not.toBe("fixed-enterprise-v1");
    expect(secondId).not.toBe(firstId);
  });

  it("ships a default manifest with only unconfounded primary model contrasts", () => {
    model.addManifest();

    const manifest: {
      model_variants: { id: string; require_pre_attack_feasibility: boolean }[];
      analysis: {
        primary_comparisons: {
          strategy: string;
          model_variant: string;
          baseline: string;
          baseline_model_variant: string;
        }[];
      };
    } = JSON.parse(model.editorText);
    const variants = Object.fromEntries(
      manifest.model_variants.map((variant) => [variant.id, variant]),
    );
    const modelContrasts = manifest.analysis.primary_comparisons
      .filter((c) => c.baseline !== "cvss")
      .map((c) => [c.model_variant, c.baseline_model_variant]);

    expect(variants.blast_only.require_pre_attack_feasibility).toBe(true);
    expect(variants.full_unconstrained.require_pre_attack_feasibility).toBe(
      false,
    );
    expect(modelContrasts).toEqual([
      ["blast_only", "full"],
      ["full_unconstrained", "full"],
    ]);
    expect(manifest.analysis.primary_comparisons).toContainEqual({
      strategy: "simulation_informed",
      model_variant: "full",
      baseline: "cvss",
      baseline_model_variant: "full",
      budget: 1,
      outcome: "blast_radius",
    });
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
      { id: "m1", manifest_id: "fixed-enterprise-v1", title: "T" },
    ];
    vi.mocked(dashboardApi.getManifest).mockResolvedValue({
      manifest: {
        id: "m1",
        manifest_id: "fixed-enterprise-v1",
        title: "T",
        content: validContent,
      },
    });
    await model.selectManifest("m1");
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
      existing_manifest_id: "m1",
    });
  });

  it("omits the existing manifest id when copying an edited manifest", async () => {
    vi.mocked(dashboardApi.getManifest).mockResolvedValue({
      manifest: {
        id: "m1",
        manifest_id: "fixed-enterprise-v1",
        title: "Old",
        content: validContent,
      },
    });
    await model.selectManifest("m1");
    model.title = "Copy";
    vi.mocked(dashboardApi.saveManifest).mockResolvedValue({
      status: "ok",
      manifest: {
        id: "m2",
        manifest_id: "fixed-enterprise-v1-copy",
        title: "Copy",
        content: { ...validContent, id: "fixed-enterprise-v1-copy" },
      },
      errors: [],
    });

    const ok = await model.save();

    expect(ok).toBe(true);
    expect(dashboardApi.saveManifest).toHaveBeenCalledWith({
      manifest_id: expect.any(String),
      title: "Copy",
      content: expect.objectContaining({ id: expect.any(String) }),
    });
  });

  it("surfaces validation errors from the backend", async () => {
    model.title = "T";
    model.editorText = JSON.stringify(
      { ...validContent, strategy_runs: [] },
      null,
      2,
    );
    vi.mocked(dashboardApi.saveManifest).mockResolvedValue({
      status: "invalid_manifest",
      manifest: null,
      errors: [{ path: "strategy_runs", message: "must not be empty" }],
    });

    const ok = await model.save();

    expect(ok).toBe(false);
    expect(model.errors).toEqual([
      { path: "strategy_runs", message: "must not be empty" },
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
    model.editorText = JSON.stringify({
      ...validContent,
      strategy_runs: validContent.strategy_runs.slice(0, 1),
    });

    expect(model.canStart).toBe(false);
    await expect(model.start()).resolves.toBe(false);
    expect(dashboardApi.startEvaluation).not.toHaveBeenCalled();
  });
});
