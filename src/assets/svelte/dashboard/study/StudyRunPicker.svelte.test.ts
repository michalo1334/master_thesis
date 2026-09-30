import type { StudyTierRunSummary } from "../../contracts.generated/dashboard/evaluation";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import StudyRunPicker from "./StudyRunPicker.svelte";

const runs: StudyTierRunSummary[] = [
  {
    id: "run-1",
    manifest_id: "manifest-1",
    manifest_title: "Baseline manifest",
    graph_title: "Gateway",
    completed_at: "2026-01-02T03:04:05Z",
    plan_count: 5,
    trial_count: 50,
  },
  {
    id: "run-2",
    manifest_id: "manifest-2",
    manifest_title: "Alternative manifest",
    graph_title: "Core",
    completed_at: "2026-02-03T04:05:06Z",
    plan_count: 6,
    trial_count: 60,
  },
];

function renderPicker(overrides: Record<string, unknown> = {}) {
  const onSelect = vi.fn();
  const onOpenChange = vi.fn();
  render(StudyRunPicker, {
    props: {
      open: true,
      tier: "small",
      runs,
      onSelect,
      onOpenChange,
      ...overrides,
    },
  });
  return { onSelect, onOpenChange };
}

afterEach(cleanup);

describe("StudyRunPicker", () => {
  it("lists eligible completed runs with metadata", () => {
    renderPicker();

    expect(screen.getByText("Baseline manifest")).toBeInTheDocument();
    expect(screen.getByText("Alternative manifest")).toBeInTheDocument();
    expect(screen.getByText("Gateway")).toBeInTheDocument();
    expect(screen.getByText("50")).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Completed runs for small" }),
    ).toBeInTheDocument();
  });

  it("filters runs by the search field", async () => {
    renderPicker();

    await fireEvent.input(
      screen.getByPlaceholderText("Search completed runs…"),
      {
        target: { value: "Alternative" },
      },
    );

    expect(screen.queryByText("Baseline manifest")).not.toBeInTheDocument();
    expect(screen.getByText("Alternative manifest")).toBeInTheDocument();
  });

  it("returns the selected run id", async () => {
    const { onSelect, onOpenChange } = renderPicker();

    await fireEvent.click(screen.getByRole("radio", { name: "Select run-2" }));
    await fireEvent.click(screen.getByRole("button", { name: "Select" }));

    await waitFor(() => expect(onSelect).toHaveBeenCalledWith("run-2"));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it("explains when no completed run qualifies", () => {
    renderPicker({ runs: [] });

    expect(
      screen.getByText("No completed evaluation run qualifies for this tier."),
    ).toBeInTheDocument();
  });
});
