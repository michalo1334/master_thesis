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
    metadata: {
      command_mode: "analyze",
      manifest_id: "manifest-1",
      model_version: "model-1",
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
            baseline: "baseline",
            budget: 1,
            comparison: -0.25,
            outcome: "improved",
          },
        ],
      }),
    });
    await waitFor(() => expect(screen.getByText("patch")).toBeInTheDocument());
    expect(screen.getByText("-0.250")).toBeInTheDocument();
    expect(screen.getByText("improved")).toBeInTheDocument();
    expect(
      screen.getByText("tested strategy minus baseline", { selector: "dd" }),
    ).toBeInTheDocument();
  });
});
