import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import { SimulationReportDocument } from "../../simulation-report/SimulationReportDocument.svelte";
import ReportInspector from "./ReportInspector.svelte";

afterEach(cleanup);

describe("ReportInspector", () => {
  it("renders the report title", async () => {
    const document = new SimulationReportDocument("Topology", "g1", "r1");
    document.markReady("report-1");

    render(ReportInspector, {
      props: {
        document,
      },
    });

    expect(screen.getByText("Report for Topology")).toBeInTheDocument();
  });
});
