import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import SimulationReport from "./SimulationReport.svelte";
import { SimulationReportDocument } from "./SimulationReportDocument.svelte";

afterEach(cleanup);

describe("SimulationReport", () => {
  it("opens the source graph without awaiting the callback", async () => {
    const onOpenSourceGraph = vi.fn(() => new Promise<boolean>(() => {}));
    const document = new SimulationReportDocument(
      "Topology",
      "graph-1",
      "revision-1",
    );

    render(SimulationReport, { props: { document, onOpenSourceGraph } });
    await fireEvent.click(
      screen.getByRole("button", { name: "Open source graph" }),
    );

    expect(onOpenSourceGraph).toHaveBeenCalledOnce();
  });
});
