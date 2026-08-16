import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import { SimulationReportDocument } from "../../simulation-report/SimulationReportDocument.svelte";
import ReportInspector from "./ReportInspector.svelte";

afterEach(cleanup);

describe("ReportInspector", () => {
  it("persists the selected analysis and shows save status", async () => {
    const document = new SimulationReportDocument("Topology", "g1", "r1");
    document.markReady("report-1");
    const onAnalysisChange = vi.fn(async (analysisId: string | null) => {
      document.setAnalysis(
        analysisId ? { id: analysisId, title: "Baseline" } : null,
      );
      return true;
    });

    render(ReportInspector, {
      props: {
        document,
        analyses: [{ id: "analysis-1", title: "Baseline" }],
        onAnalysisChange,
      },
    });

    await fireEvent.change(screen.getByRole("combobox", { name: "Analysis" }), {
      target: { value: "analysis-1" },
    });

    expect(onAnalysisChange).toHaveBeenCalledWith("analysis-1");
    expect(document.analysisTitle).toBe("Baseline");
    expect(screen.getByRole("status")).toHaveTextContent("Saved.");
  });
});
