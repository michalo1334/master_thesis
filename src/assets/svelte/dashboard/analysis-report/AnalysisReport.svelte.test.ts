import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/svelte";
import AnalysisReport from "./AnalysisReport.svelte";
import { AnalysisReportDocument } from "./AnalysisReportDocument.svelte";

afterEach(cleanup);

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
});
