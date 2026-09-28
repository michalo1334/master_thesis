import { describe, expect, it, vi } from "vitest";
import { AnalysisReportDocument } from "./AnalysisReportDocument.svelte";

const analysis = {
  capability_results: [],
  feasibility_summary: [],
  metadata: {
    command_mode: "analyze",
    manifest_id: "m",
    model_version: "v",
    runtime_summary: {
      median_plan_selection_runtime_ms: 0,
      median_simulation_runtime_ms: 0,
      evaluator_runtime_ms: 0,
    },
    schema_version: 1,
  },
  pilot_results: [],
  primary_results: [],
  secondary_results: [],
};

describe("AnalysisReportDocument statistical analysis", () => {
  it("loads the final session on a request and routes ready and error events by mode", async () => {
    const document = new AnalysisReportDocument("run-1", {
      manifest_id: "m",
      title: "M",
    });
    const api = {
      requestEvaluationAnalysis: vi
        .fn()
        .mockResolvedValue({ status: "processing" }),
    };

    const first = document.startAnalysis(api as never, document.id);
    expect(document.finalAnalysis.status).toBe("loading");
    await document.startAnalysis(api as never, document.id);
    expect(api.requestEvaluationAnalysis).toHaveBeenCalledTimes(1);
    await first;
    expect(api.requestEvaluationAnalysis).toHaveBeenCalledWith({
      document_id: document.id,
      run_id: "run-1",
    });

    document.setAnalysisReady({
      document_id: "other",
      run_id: "run-1",
      mode: "analyze",
      analysis,
    });
    expect(document.finalAnalysis.status).toBe("loading");

    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "analyze",
      analysis,
    });
    expect(document.finalAnalysis.status).toBe("loaded");
    expect(document.pilotAnalysis.status).toBe("idle");

    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "pilot",
      analysis,
    });
    expect(document.pilotAnalysis.status).toBe("loaded");

    document.setAnalysisError({
      document_id: document.id,
      run_id: "run-1",
      mode: "analyze",
      error: { code: "invalid_analysis" },
    });
    expect(document.finalAnalysis.status).toBe("error");
    document.markReady();
    expect(document.pilotAnalysis.status).toBe("idle");
    expect(document.finalAnalysis.status).toBe("idle");
  });
});
