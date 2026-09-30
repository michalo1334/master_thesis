import type { StudySpecificationSummary } from "../../contracts.generated/dashboard/evaluation";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import type { DashboardApi } from "../dashboard-api";
import StudyDialog from "./StudyDialog.svelte";
import { StudyModel } from "./StudyModel.svelte";
import { createDefaultStudySpecification } from "./study-types";

function specificationSummary(
  tiers: string[] = ["small"],
): StudySpecificationSummary {
  const content = JSON.parse(createDefaultStudySpecification("study-one"));
  content.tiers = tiers;
  return {
    id: "spec-1",
    study_id: "study-one",
    specification_version: 1,
    title: "Study one",
    content,
  };
}

function studyApi(tiers: string[] = ["small"]) {
  const summary = specificationSummary(tiers);
  return {
    listStudySpecifications: vi
      .fn()
      .mockResolvedValue({ specifications: [summary] }),
    getStudySpecification: vi
      .fn()
      .mockResolvedValue({ specification: summary }),
    saveStudySpecification: vi.fn(),
    describeStudySpecification: vi.fn(),
    listStudyTierRuns: vi.fn().mockResolvedValue({
      runs: [
        {
          id: "run-1",
          manifest_id: "manifest-1",
          manifest_title: "Baseline manifest",
          graph_title: "Gateway",
          completed_at: "2026-01-02T03:04:05Z",
          plan_count: 5,
          trial_count: 50,
        },
      ],
    }),
    preflightStudy: vi.fn().mockResolvedValue({ status: "ok", errors: [] }),
    startStudyAnalysis: vi.fn(),
  };
}

async function selectSaved(model: StudyModel): Promise<void> {
  await model.selectSpecification("spec-1");
  await waitFor(() => expect(model.isLoadingRuns).toBe(false));
}

async function renderDialog() {
  const api = studyApi();
  const model = new StudyModel(api as unknown as DashboardApi);
  render(StudyDialog, { props: { model } });
  await model.openDialog();
  return { api, model };
}

afterEach(cleanup);

describe("StudyDialog", () => {
  it("lists saved versions with JSON, Preview, and Run tabs", async () => {
    const { model } = await renderDialog();

    expect(screen.getByRole("tab", { name: "JSON" })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Preview" })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Run" })).toBeInTheDocument();
    expect(screen.getByText("Study one")).toBeInTheDocument();
    expect(screen.getByText("study-one v1")).toBeInTheDocument();
    expect(model.open).toBe(true);
  });

  it("requires a saved immutable version before tier mapping", async () => {
    const { model } = await renderDialog();

    await fireEvent.click(screen.getByRole("tab", { name: "Run" }));

    expect(
      screen.getByText(
        "Save an immutable specification version to map declared tiers.",
      ),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Run pilot" }),
    ).not.toBeInTheDocument();
  });

  it("shows one compact row per declared tier for a saved version", async () => {
    const { model } = await renderDialog();
    await selectSaved(model);

    await fireEvent.click(screen.getByRole("tab", { name: "Run" }));

    expect(screen.getByText(/0 of 1 tiers mapped/)).toHaveTextContent(
      "study-one v1",
    );
    expect(
      screen.getByRole("rowheader", { name: "small" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Choose run for tier small" }),
    ).toBeInTheDocument();
  });

  it("returns to the unsaved notice when the title changes", async () => {
    const { model } = await renderDialog();
    await selectSaved(model);
    await fireEvent.click(screen.getByRole("tab", { name: "Run" }));
    expect(
      screen.getByRole("rowheader", { name: "small" }),
    ).toBeInTheDocument();

    await fireEvent.input(screen.getByLabelText("Title"), {
      target: { value: "Renamed" },
    });

    expect(
      screen.getByText(
        "Save an immutable specification version to map declared tiers.",
      ),
    ).toBeInTheDocument();
  });

  it("disables Save and keeps Save as new version after editing a saved version", async () => {
    const { model } = await renderDialog();
    await selectSaved(model);

    expect(screen.getByRole("button", { name: "Save" })).toBeEnabled();

    await fireEvent.input(screen.getByLabelText("Study JSON"), {
      target: { value: `${model.editorText}\n` },
    });

    expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();
    expect(
      screen.getByRole("button", { name: "Save as new version" }),
    ).toBeEnabled();
  });

  it("shows the required input shape in the tier row", async () => {
    const api = studyApi();
    api.listStudyTierRuns.mockResolvedValue({
      runs: [
        {
          id: "run-1",
          manifest_id: "manifest-1",
          manifest_title: "Baseline manifest",
          graph_title: "Gateway",
          completed_at: "2026-01-02T03:04:05Z",
          plan_count: 5,
          trial_count: 50,
        },
      ],
      required_inputs: "1 model variant · strategies: simulation_informed",
    });
    const model = new StudyModel(api as unknown as DashboardApi);
    render(StudyDialog, { props: { model } });
    await model.openDialog();
    await selectSaved(model);

    await fireEvent.click(screen.getByRole("tab", { name: "Run" }));

    expect(
      screen.getByRole("cell", { name: /strategies: simulation_informed/ }),
    ).toBeInTheDocument();
  });

  it("opens the filtered completed-run picker from a tier row", async () => {
    const { model } = await renderDialog();
    await selectSaved(model);
    await fireEvent.click(screen.getByRole("tab", { name: "Run" }));

    await fireEvent.click(
      screen.getByRole("button", { name: "Choose run for tier small" }),
    );

    expect(
      await screen.findByRole("heading", { name: "Completed runs for small" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Baseline manifest")).toBeInTheDocument();
  });

  it("offers the evaluation manifest when no completed run qualifies", async () => {
    const api = studyApi();
    api.listStudyTierRuns.mockResolvedValue({ runs: [] });
    const model = new StudyModel(api as unknown as DashboardApi);
    const onOpenEvaluationManifest = vi.fn();
    model.onOpenEvaluationManifest = onOpenEvaluationManifest;
    render(StudyDialog, { props: { model } });
    await model.openDialog();
    await selectSaved(model);

    await fireEvent.click(screen.getByRole("tab", { name: "Run" }));
    await fireEvent.click(
      screen.getByRole("button", { name: "Open evaluation manifest" }),
    );

    expect(onOpenEvaluationManifest).toHaveBeenCalledOnce();
    expect(model.open).toBe(false);
  });

  it("shows a row message and summary for a partial mapping without generic mismatch text", async () => {
    const api = studyApi(["small", "large"]);
    api.listStudyTierRuns.mockImplementation(
      async (payload: { tier: string }) => ({
        runs: [
          {
            id: `run-${payload.tier}`,
            manifest_id: `manifest-${payload.tier}`,
            manifest_title: `${payload.tier} manifest`,
            graph_title: "Gateway",
            completed_at: "2026-01-02T03:04:05Z",
            plan_count: 5,
            trial_count: 50,
          },
        ],
      }),
    );
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
    const model = new StudyModel(api as unknown as DashboardApi);
    render(StudyDialog, { props: { model } });
    await model.openDialog();
    await selectSaved(model);
    await fireEvent.click(screen.getByRole("tab", { name: "Run" }));

    model.selectRun("small", "run-small");

    await waitFor(() =>
      expect(
        screen.getByText(
          "A selected evaluation run does not match the required study inputs.",
        ),
      ).toBeInTheDocument(),
    );
    expect(
      screen.getByText("Select one completed run for every declared tier."),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Select one completed run for this tier."),
    ).toBeInTheDocument();
    expect(
      screen.queryByText("The mapping does not match the declared tiers."),
    ).not.toBeInTheDocument();
  });

  it("enables Run pilot after a successful preflight", async () => {
    const { model } = await renderDialog();
    await selectSaved(model);
    await fireEvent.click(screen.getByRole("tab", { name: "Run" }));

    expect(screen.getByRole("button", { name: "Run pilot" })).toBeDisabled();

    model.selectRun("small", "run-1");

    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Run pilot" })).toBeEnabled(),
    );
  });
});
