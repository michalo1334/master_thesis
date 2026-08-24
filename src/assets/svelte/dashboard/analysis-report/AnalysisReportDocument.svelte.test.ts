import { describe, expect, it, vi } from "vitest";
import { AnalysisReportDocument } from "./AnalysisReportDocument.svelte";

const analysis = {
  capability_results: [],
  metadata: {
    command_mode: "analyze",
    manifest_id: "m",
    model_version: "v",
    schema_version: 1,
  },
  pilot_comparison_pass: [],
  primary_results: [],
  secondary_results: [],
};

describe("AnalysisReportDocument statistical analysis", () => {
  it("tracks independent sessions and ignores mismatched events and duplicate requests", async () => {
    const document = new AnalysisReportDocument("run-1", {
      manifest_id: "m",
      title: "M",
    });
    const api = {
      requestEvaluationAnalysis: vi
        .fn()
        .mockResolvedValue({ status: "processing" }),
    };

    const first = document.startAnalysis(api as never, document.id, "pilot");
    expect(document.pilotAnalysis.status).toBe("loading");
    await document.startAnalysis(api as never, document.id, "pilot");
    expect(api.requestEvaluationAnalysis).toHaveBeenCalledTimes(1);
    await first;

    document.setAnalysisReady({
      document_id: "other",
      run_id: "run-1",
      mode: "pilot",
      analysis,
    });
    expect(document.pilotAnalysis.status).toBe("loading");
    document.setAnalysisReady({
      document_id: document.id,
      run_id: "run-1",
      mode: "pilot",
      analysis,
    });
    expect(document.pilotAnalysis.status).toBe("loaded");
    expect(document.finalAnalysis.status).toBe("idle");

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
