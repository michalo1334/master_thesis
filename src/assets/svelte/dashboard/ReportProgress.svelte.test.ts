import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/svelte";
import ReportProgress from "./ReportProgress.svelte";

afterEach(cleanup);

describe("ReportProgress", () => {
  it("renders a determinate progress bar with a detail line", () => {
    render(ReportProgress, {
      props: {
        progress: { completed: 2, total: 5, detail: "Scoring defenses" },
        waitingMessage: "Optimization requested, waiting for progress...",
        label: "steps completed",
      },
    });

    const bar = screen.getByRole("progressbar", {
      name: "2 of 5 steps completed",
    });
    expect(bar).toHaveAttribute("max", "5");
    expect(bar).toHaveAttribute("value", "2");
    expect(screen.getByText("2 of 5 steps completed")).toBeInTheDocument();
    expect(screen.getByText("Scoring defenses")).toBeInTheDocument();
    expect(
      screen.queryByText("Optimization requested, waiting for progress..."),
    ).not.toBeInTheDocument();
  });

  it("renders the waiting message without a progress bar when indeterminate", () => {
    render(ReportProgress, {
      props: {
        progress: null,
        waitingMessage: "Loading report...",
        label: "runs completed",
      },
    });

    expect(screen.getByText("Loading report...")).toBeInTheDocument();
    expect(screen.queryByRole("progressbar")).not.toBeInTheDocument();
  });
});
