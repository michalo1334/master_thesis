import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import AnalysisReport from "./AnalysisReport.svelte";
import { AnalysisReportDocument } from "./AnalysisReportDocument.svelte";
import type { DashboardApi } from "../dashboard-api";
import type { EvaluationAnalysis } from "../../contracts.generated";

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
    pilot_comparison_pass: [],
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

  it("runs pilot analysis and renders a matching ready result", async () => {
    const document = loadedDocument();
    const api = apiFixture();
    await openStatisticalAnalysis(document, api);

    await fireEvent.click(screen.getByRole("button", { name: "Run pilot" }));
    expect(api.requestEvaluationAnalysis).toHaveBeenCalledWith({
      document_id: document.id,
      run_id: "run-1",
      mode: "pilot",
    });

    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "pilot",
      analysis: analysisFixture({
        pilot_comparison_pass: [{ comparison: 0.125, passes: true }],
      }),
    });
    await waitFor(() => expect(screen.getByText("0.125")).toBeInTheDocument());
    expect(
      screen.getByRole("heading", { name: "Pilot planning results" }),
    ).toBeInTheDocument();
  });

  it("announces pilot errors", async () => {
    const document = loadedDocument();
    const api = apiFixture({ status: "rejected" });
    await openStatisticalAnalysis(document, api);

    await fireEvent.click(screen.getByRole("button", { name: "Run pilot" }));

    expect(
      await screen.findByText("Unable to start pilot analysis (rejected)."),
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
      mode: "analyze",
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
          pilot_all_pass: true,
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
