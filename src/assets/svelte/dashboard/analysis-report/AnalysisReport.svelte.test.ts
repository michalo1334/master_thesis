import type { EvaluationAnalysis } from "../../contracts.generated/dashboard/evaluation";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/svelte";
import AnalysisReport from "./AnalysisReport.svelte";
import { AnalysisReportDocument } from "./AnalysisReportDocument.svelte";
import type { DashboardApi } from "../dashboard-api";
afterEach(cleanup);

function loadedDocument(): AnalysisReportDocument {
  const document = new AnalysisReportDocument("run-1", {
    manifest_id: "manifest-1",
    title: "Evaluation manifest",
  });
  document.setReportData({
    run_id: "run-1",
    graph_id: "graph-1",
    manifest_id: "manifest-1",
    manifest_title: "Evaluation manifest",
    source_graph_revision_id: "revision-1",
    source_graph_title: "Graph",
    status: "completed",
    plans: [],
    experiments: [],
  });
  return document;
}

function analysisFixture(
  overrides: Partial<EvaluationAnalysis> = {},
): EvaluationAnalysis {
  return {
    capability_results: [],
    feasibility_summary: [],
    metadata: {
      command_mode: "analyze",
      manifest_id: "manifest-1",
      model_version: "model-1",
      model_variants: [
        { id: "full", objective: "mission_then_blast_radius" },
        { id: "blast_only_unconstrained", objective: "blast_radius_only" },
      ],
      runtime_summary: {
        median_plan_selection_runtime_ms: 25,
        median_simulation_runtime_ms: 50,
        evaluator_runtime_ms: 75,
      },
      schema_version: 1,
      estimand_note: "tested strategy minus baseline",
    },
    pilot_results: [],
    primary_results: [],
    secondary_results: [],
    ...overrides,
  };
}

function apiFixture(reply = { status: "processing" }): DashboardApi {
  return {
    requestEvaluationAnalysis: vi.fn().mockResolvedValue(reply),
  } as unknown as DashboardApi;
}

function surveyPilotFixture(
  metadata: {
    recommended_plan_selection_seed_count: number | null;
    recommended_attacks_per_plan: number | null;
    insufficient_pilot: boolean;
  },
  informative = true,
): EvaluationAnalysis {
  return analysisFixture({
    metadata: {
      ...analysisFixture().metadata,
      command_mode: "study-pilot",
      family_scope: "study",
      family_size: 36,
      ...metadata,
    },
    pilot_results: [
      {
        comparison_id: "small|full|simulation_informed|cvss|1|mission_impact",
        tier: "small",
        informative,
        candidate_plan_count: 6,
        candidate_attacks_per_plan: 12,
        guarded_ci_half_width: informative ? 0.5 : 0,
        target: 1,
        passes: informative,
      },
    ],
  });
}

function studyPrimaryRow(
  overrides: Partial<EvaluationAnalysis["primary_results"][number]> = {},
): EvaluationAnalysis["primary_results"][number] {
  return {
    comparison: 0,
    comparison_id: "small|full|simulation_informed|cvss|1|mission_impact",
    tier: "small",
    strategy: "simulation_informed",
    model_variant: "full",
    baseline: "cvss",
    baseline_model_variant: "full",
    budget: 1,
    outcome: "mission_impact",
    informative: true,
    tested_plan_count: 6,
    baseline_plan_count: 6,
    attacks_per_plan: 12,
    paired_mean_difference: -0.5,
    ci_lower: -1,
    ci_upper: 0,
    ci_half_width: 0.5,
    p_raw: 0.02,
    p_adjusted: 0.04,
    ...overrides,
  };
}

async function openStatisticalAnalysis(
  document: AnalysisReportDocument,
  api: DashboardApi,
) {
  render(AnalysisReport, { props: { document, api } });
  await fireEvent.click(
    screen.getByRole("tab", { name: "Statistical analysis" }),
  );
}

describe("AnalysisReport", () => {
  it("labels progress by total evaluation work", () => {
    const document = new AnalysisReportDocument("run-1", {
      manifest_id: "manifest-1",
      title: "Evaluation manifest",
    });
    document.setProgress(4, 13, "Baseline attack trials: 3 of 5");

    render(AnalysisReport, { props: { document } });

    expect(
      screen.getByRole("progressbar", {
        name: "4 of 13 evaluation steps completed",
      }),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Baseline attack trials: 3 of 5"),
    ).toBeInTheDocument();
  });

  it("shows report assembly progress while loading", () => {
    const document = new AnalysisReportDocument("run-1", {
      manifest_id: "manifest-1",
      title: "Evaluation manifest",
    });
    document.load(
      { requestEvaluationReport: () => {} } as never,
      "document-1",
      "run-1",
    );
    document.setLoadProgress(2, 4, "Summarizing plans");

    render(AnalysisReport, { props: { document } });

    expect(
      screen.getByRole("progressbar", {
        name: "2 of 4 assembly steps completed",
      }),
    ).toBeInTheDocument();
    expect(screen.getByText("Summarizing plans")).toBeInTheDocument();
  });

  it("keeps the report tab first and adds statistical analysis", () => {
    const document = loadedDocument();

    render(AnalysisReport, { props: { document } });

    const tabs = screen.getAllByRole("tab");
    expect(tabs[0]).toHaveTextContent("Report");
    expect(tabs[1]).toHaveTextContent("Statistical analysis");
    expect(screen.getByRole("heading", { name: "Summary" })).toBeVisible();
  });

  it("renders a study-pilot ready result", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);

    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "pilot",
      analysis: surveyPilotFixture({
        recommended_plan_selection_seed_count: 6,
        recommended_attacks_per_plan: 12,
        insufficient_pilot: false,
      }),
    });
    await waitFor(() => expect(screen.getByText("small")).toBeInTheDocument());
    expect(
      screen.getByRole("heading", { name: "Pilot planning results" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("columnheader", { name: "Guarded half-width" }),
    ).toBeInTheDocument();
  });

  it("announces study-pilot errors", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);

    document.setAnalysisError({
      document_id: document.id,
      run_id: "run-1",
      mode: "pilot",
      error: { code: "invalid_analysis" },
    });

    expect(
      await screen.findByText("Analysis failed (invalid_analysis)."),
    ).toBeInTheDocument();
  });

  it("runs final analysis and renders primary results and the sign convention", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);

    await fireEvent.click(
      screen.getByRole("button", { name: "Run final analysis" }),
    );
    expect(api.requestEvaluationAnalysis).toHaveBeenCalledWith({
      document_id: document.id,
      run_id: "run-1",
    });

    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "analyze",
      analysis: analysisFixture({
        primary_results: [
          {
            strategy: "patch",
            model_variant: "full",
            baseline: "baseline",
            baseline_model_variant: "full",
            budget: 1,
            comparison: -0.25,
            outcome: "improved",
          },
        ],
      }),
    });
    await waitFor(() =>
      expect(screen.getByText("patch (full)")).toBeInTheDocument(),
    );
    expect(screen.getByText("baseline (full)")).toBeInTheDocument();
    expect(screen.getByText("-0.250")).toBeInTheDocument();
    expect(screen.getByText("improved")).toBeInTheDocument();
    expect(
      screen.getByText("tested strategy minus baseline", { selector: "dd" }),
    ).toBeInTheDocument();
  });

  it("separates scalar metadata from reproducibility metadata", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);
    const longHash = "sha256-" + "a".repeat(180);
    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "analyze",
      analysis: analysisFixture({
        metadata: {
          ...analysisFixture().metadata,
          checksums_hash: longHash,
          input_hashes: { graph: "graph-hash", manifest: "manifest-hash" },
          analysis_configuration: {
            alpha: 0.05,
            contrasts: ["patch", "baseline"],
          },
          dependencies: { python: "3.12", scipy: "1.14" },
          input_trial_count: 100,
          declared_plan_trial_count: 100,
          analysis_runtime_seconds: 2.5,
          simulator_only_uncertainty: true,
          package_version: "1.2.3",
        },
      }),
    });

    await waitFor(() =>
      expect(
        screen.getByRole("region", { name: "Key performance indicators" }),
      ).toBeInTheDocument(),
    );
    const kpis = screen.getByRole("region", {
      name: "Key performance indicators",
    });
    expect(kpis).toHaveTextContent("Declared plan trials");
    expect(kpis).not.toHaveTextContent("Manifest ID");
    expect(
      screen.getByRole("heading", { name: "Reproducibility" }),
    ).toBeInTheDocument();
    expect(screen.getByText(longHash)).toBeInTheDocument();
    expect(screen.getByText("graph")).toBeInTheDocument();
    expect(screen.getByText("graph-hash")).toBeInTheDocument();
    expect(screen.getByText("alpha")).toBeInTheDocument();
    expect(screen.getByText("0.050")).toBeInTheDocument();
    expect(screen.getByText("python")).toBeInTheDocument();
    expect(screen.getByText("3.12")).toBeInTheDocument();
    expect(screen.getByText("Model variants")).toBeInTheDocument();
    expect(
      screen.getByText(/blast_only_unconstrained/, { selector: "pre" }),
    ).toBeInTheDocument();
  });

  it("shows archive timing and pre-attack feasibility summaries", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);
    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "analyze",
      analysis: analysisFixture({
        feasibility_summary: [
          {
            experiment_id: "baseline-experiment",
            plan_id: "",
            pre_attack_feasible: false,
            unavailable_required_flow_count: 2,
            affected_capability_count: 1,
          },
          {
            experiment_id: "plan-experiment",
            plan_id: "plan-1",
            pre_attack_feasible: true,
            unavailable_required_flow_count: 0,
            affected_capability_count: 0,
          },
        ],
        metadata: {
          ...analysisFixture().metadata,
          runtime_summary: {
            median_plan_selection_runtime_ms: 1250,
            median_simulation_runtime_ms: 500,
            evaluator_runtime_ms: 2500,
          },
        },
      }),
    });

    await waitFor(() =>
      expect(
        screen.getByRole("heading", { name: "Archive runtime summary" }),
      ).toBeInTheDocument(),
    );
    expect(screen.getByText("1.3 s")).toBeInTheDocument();
    expect(screen.getByText("500 ms")).toBeInTheDocument();
    expect(screen.getByText("2.5 s")).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Pre-attack feasibility" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Baseline")).toBeInTheDocument();
    expect(screen.getByText("plan-1")).toBeInTheDocument();
    expect(screen.getByText("Infeasible")).toBeInTheDocument();
    expect(screen.getByText("Feasible")).toBeInTheDocument();
  });

  it("shows capability names and opens their graph nodes", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    const openSourceGraph = vi.fn().mockResolvedValue(true);
    document.openSourceGraph = openSourceGraph;
    await openStatisticalAnalysis(document, api);
    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "analyze",
      analysis: analysisFixture({
        capability_results: [
          {
            capability_id: "capability-1",
            capability_name: "  Mission communications  ",
            strategy: "patch",
            model_variant: "full",
            baseline: "baseline",
            baseline_model_variant: "blast_only_unconstrained",
            budget: 1,
            comparison: 0.1,
          },
        ],
      }),
    });

    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Mission communications" }),
      ).toBeInTheDocument(),
    );
    expect(screen.getByText("patch (full)")).toBeInTheDocument();
    expect(
      screen.getByText("baseline (blast_only_unconstrained)"),
    ).toBeInTheDocument();
    await fireEvent.click(
      screen.getByRole("button", { name: "Mission communications" }),
    );
    expect(openSourceGraph).toHaveBeenCalledWith("capability-1");
    expect(
      screen.getByRole("button", { name: "Mission communications" }),
    ).toHaveAttribute("title", "capability-1");
  });

  it("renders the study pilot recommendation summary", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);
    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "pilot",
      analysis: surveyPilotFixture({
        recommended_plan_selection_seed_count: 6,
        recommended_attacks_per_plan: 12,
        insufficient_pilot: false,
      }),
    });

    await waitFor(() =>
      expect(screen.getByText("Recommended plan count")).toBeInTheDocument(),
    );
    expect(
      screen.getByText("Recommended attacks per plan"),
    ).toBeInTheDocument();
    expect(screen.getByText("Candidate plans")).toBeInTheDocument();
    expect(
      screen.getByRole("columnheader", { name: "Guarded half-width" }),
    ).toBeInTheDocument();

    const summary = screen.getByText("Recommended plan count").closest("dl");
    expect(summary).not.toBeNull();
    expect(within(summary!).getByText("6")).toBeInTheDocument();
    expect(within(summary!).getByText("12")).toBeInTheDocument();
    expect(
      within(summary!).getByText("Recommendation available"),
    ).toBeInTheDocument();
  });

  it("renders the insufficient pilot state", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);
    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "pilot",
      analysis: surveyPilotFixture({
        recommended_plan_selection_seed_count: null,
        recommended_attacks_per_plan: null,
        insufficient_pilot: true,
      }),
    });

    expect(await screen.findByText("Insufficient pilot")).toBeInTheDocument();
  });

  it("shows the non-informative pilot count and blocking warning", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);
    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "pilot",
      analysis: surveyPilotFixture(
        {
          recommended_plan_selection_seed_count: null,
          recommended_attacks_per_plan: null,
          insufficient_pilot: true,
        },
        false,
      ),
    });

    await waitFor(() =>
      expect(
        screen.getByText("Non-informative comparisons"),
      ).toBeInTheDocument(),
    );
    const summary = screen
      .getByText("Non-informative comparisons")
      .closest("dl");
    expect(within(summary!).getByText("1")).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent("non-informative");
  });

  it("labels the study-family Holm adjustment", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);
    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "analyze",
      analysis: analysisFixture({
        metadata: {
          ...analysisFixture().metadata,
          command_mode: "study-analyze",
          family_scope: "study",
          family_size: 36,
        },
        primary_results: [studyPrimaryRow()],
      }),
    });

    expect(
      await screen.findByText(
        "Holm adjustment covers the complete declared study family.",
      ),
    ).toBeInTheDocument();
  });

  it("shows a blocking warning for non-informative primary comparisons", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);
    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "analyze",
      analysis: analysisFixture({
        metadata: {
          ...analysisFixture().metadata,
          command_mode: "study-analyze",
          family_scope: "study",
          family_size: 36,
        },
        primary_results: [
          studyPrimaryRow({
            informative: false,
            paired_mean_difference: 0,
            ci_half_width: 0,
          }),
        ],
      }),
    });

    await waitFor(() =>
      expect(screen.getByText("Comparison ID")).toBeInTheDocument(),
    );
    expect(
      screen.getByRole("columnheader", { name: "Tested plans" }),
    ).toBeInTheDocument();
    const alert = screen.getByRole("alert");
    expect(alert).toHaveTextContent("non-informative");
    expect(alert).toHaveTextContent("not a pass");
  });

  it("falls back to the capability UUID when its name is missing", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);
    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "analyze",
      analysis: analysisFixture({
        capability_results: [
          {
            capability_id: "capability-2",
            strategy: "patch",
            model_variant: "full",
            baseline: "baseline",
            baseline_model_variant: "full",
            budget: 1,
            comparison: 0.1,
          },
        ],
      }),
    });

    await waitFor(() =>
      expect(screen.getByText("capability-2")).toBeInTheDocument(),
    );
  });
});
