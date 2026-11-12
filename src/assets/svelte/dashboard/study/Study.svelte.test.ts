import { afterEach, describe, it, expect, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import { tick } from "svelte";
import Study from "./Study.svelte";
import PilotReview from "./pilot/PilotReview.svelte";
import FinalResults from "./results/FinalResults.svelte";
import ExecutionView from "./execution/ExecutionView.svelte";
import { WorkspaceModel } from "../workspace/WorkspaceModel.svelte";
import { StudyExecutionModel } from "./StudyExecutionModel.svelte";
import {
  apiFixture,
  definition,
  options,
  pilot,
  result,
  status,
} from "./test-fixtures";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});
describe("Study rendered views", () => {
  it("renders structured authoring, exact read-only YAML and authoritative freeze errors", async () => {
    const api = apiFixture((event) =>
      event === "fetch_study_options"
        ? { options }
        : {
            status: "error",
            error: {
              category: "validation_failed",
              issues: [
                {
                  code: "conflict",
                  path: ["study", "revision"],
                  message: "Choose a different revision.",
                },
              ],
            },
          },
    );
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.createStudyDraft(definition);
    document.definition.draft.revision = "1";
    render(Study, { document, api });
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Freeze revision" }),
      ).toBeEnabled(),
    );
    expect(screen.queryByRole("textbox", { name: "Study ID" })).toBeNull();
    expect(screen.queryByRole("textbox", { name: "Family ID" })).toBeNull();
    await fireEvent.input(
      screen.getByRole("textbox", { name: "Study name (optional)" }),
      { target: { value: "Defense study" } },
    );
    expect(document.title).toContain("Defense study");
    expect(
      (
        screen.getByRole("textbox", {
          name: "Read-only YAML",
        }) as HTMLTextAreaElement
      ).value,
    ).toContain("name: Defense study");
    expect(screen.getByRole("textbox", { name: "Master seed" })).toHaveValue(
      "9007199254740993",
    );
    expect(
      screen.getByRole("textbox", { name: "Read-only YAML" }),
    ).toHaveAttribute("readonly");
    await fireEvent.input(
      screen.getByRole("textbox", { name: "Master seed" }),
      { target: { value: "9007199254740995" } },
    );
    await tick();
    expect(
      (
        screen.getByRole("textbox", {
          name: "Read-only YAML",
        }) as HTMLTextAreaElement
      ).value,
    ).toContain("seed: 9007199254740995");
    vi.spyOn(globalThis, "confirm").mockReturnValue(true);
    await fireEvent.click(
      screen.getByRole("button", { name: "Freeze revision" }),
    );
    expect(api.studyRequest).toHaveBeenCalledWith("create_study_revision", {
      definition: expect.objectContaining({ name: "Defense study" }),
    });
    await waitFor(() =>
      expect(
        screen.getByText(/Choose a different revision/),
      ).toBeInTheDocument(),
    );
  });
  it("places backend issues under their fields and retains only general issues in the summary", async () => {
    const fields = [
      ["Revision", ["definition", "revision"]],
      ["Family alpha", ["definition", "family_alpha"]],
      ["Confidence level", ["definition", "confidence_level"]],
      ["Iterations per run", ["definition", "iterations_per_run"]],
      ["Maximum attempts", ["definition", "max_attempts"]],
      ["Extra pool plans", ["definition", "extra_pool_plans"]],
      ["Extra pool attacks", ["definition", "extra_pool_attacks"]],
      ["Outer subsamples", ["definition", "outer_subsamples"]],
      ["Target half-width", ["definition", "target_half_width"]],
      ["Guard quantile", ["definition", "guard_quantile"]],
      ["Candidate 1 plans per side", ["definition", "candidates", 0, "plans"]],
      [
        "Candidate 1 attacks per plan",
        ["definition", "candidates", 0, "attacks"],
      ],
      ["small budget 1", ["definition", "tiers", 0, "budgets", 0]],
      ["medium budget 1", ["definition", "tiers", 1, "budgets", 0]],
      ["large budget 1", ["definition", "tiers", 2, "budgets", 0]],
    ] as const;
    const api = apiFixture((event) =>
      event === "fetch_study_options"
        ? { options }
        : {
            status: "error",
            error: {
              category: "validation_failed",
              issues: [
                ...fields.map(([, path]) => ({
                  code: "invalid_field",
                  path: [...path],
                  message: "Supply a valid value.",
                })),
                {
                  code: "conflict",
                  path: [],
                  message: "Choose a different identity.",
                },
              ],
            },
          },
    );
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.createStudyDraft();
    render(Study, { document, api });
    await screen.findByRole("textbox", { name: "small budget 1" });
    expect(document.definition.draft.study_id).toBe(options.study_id);
    expect(document.definition.draft.family_id).toBe(options.family_id);
    expect(document.definition.draft.name).toBe("");
    vi.spyOn(globalThis, "confirm").mockReturnValue(true);
    await fireEvent.click(
      screen.getByRole("button", { name: "Freeze revision" }),
    );
    await waitFor(() =>
      expect(screen.getByRole("textbox", { name: "Revision" })).toHaveAttribute(
        "aria-invalid",
        "true",
      ),
    );
    for (const [label] of fields) {
      const input = screen.getByRole("textbox", { name: label });
      expect(input).toHaveAttribute("aria-invalid", "true");
      expect(input).toHaveAccessibleDescription("Supply a valid value.");
      const feedback = globalThis.document.getElementById(
        input.getAttribute("aria-describedby")!,
      )!;
      expect(input.parentElement).toContainElement(feedback);
    }
    expect(screen.getByRole("textbox", { name: "Revision" })).toHaveFocus();
    expect(screen.getAllByText("Supply a valid value.")).toHaveLength(
      fields.length,
    );
    expect(screen.getByText(/Choose a different identity/)).toBeInTheDocument();
    expect(screen.queryByText(/definition.revision:/)).not.toBeInTheDocument();
    expect(api.studyRequest).toHaveBeenCalledWith("create_study_revision", {
      definition: expect.objectContaining({
        revision: "",
        seed: "",
        family_alpha: "",
      }),
    });
  });

  it("renders only the accepted recommended approval action", async () => {
    const model = new StudyExecutionModel(
      "execution-1",
      "doc",
      apiFixture(),
      status("awaiting_final"),
    );
    model.pilot = pilot("recommended");
    render(PilotReview, { model });
    expect(
      screen.getByRole("button", { name: "Approve recommended candidate" }),
    ).toBeEnabled();
    expect(
      screen.queryByRole("button", { name: "Approve insufficient override" }),
    ).toBeNull();
    await fireEvent.click(screen.getByRole("radio", { name: /tiny/ }));
    await waitFor(() =>
      expect(screen.getByText(/comparison assessments/)).toBeInTheDocument(),
    );
  });
  it("requires the insufficient override safeguard", () => {
    const model = new StudyExecutionModel(
      "execution-1",
      "doc",
      apiFixture(),
      status("awaiting_final"),
    );
    model.pilot = pilot();
    render(PilotReview, { model });
    expect(
      screen.getByRole("button", { name: "Approve insufficient override" }),
    ).toBeDisabled();
    expect(
      screen.getByRole("checkbox", { name: /I accept proceeding/ }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Approve recommended candidate" }),
    ).toBeNull();
  });
  it("shows the supported unavailable error without exposing partial Final data", async () => {
    const api = apiFixture((event) =>
      event === "fetch_study_result"
        ? {
            status: "error",
            error: {
              category: "validation_failed",
              issues: [
                {
                  code: "result_not_available",
                  path: [],
                  message: "The study execution has not succeeded.",
                },
              ],
            },
          }
        : {},
    );
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.createStudyDraft();
    const model = new StudyExecutionModel(
      "execution-1",
      document.id,
      api,
      status(),
    );
    render(FinalResults, { model });
    await waitFor(() =>
      expect(screen.getByText(/result_not_available/)).toBeInTheDocument(),
    );
    expect(
      screen.queryByRole("heading", { name: "Stored Final result" }),
    ).toBeNull();
  });

  it("retains accepted failure context and offers a separate new execution", () => {
    const api = apiFixture();
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.openStudy({ study_id: "a", revision: 1 });
    const failed = {
      ...status("failed"),
      error: {
        category: "unavailable",
        issues: [
          {
            code: "clock_lost",
            path: ["final_collection"],
            message: "The measurement session ended.",
          },
        ],
      },
    };
    const model = new StudyExecutionModel(
      "execution-1",
      document.id,
      api,
      failed,
    );
    render(ExecutionView, { model, document });
    expect(screen.getByRole("alert")).toHaveTextContent("clock_lost");
    expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
    expect(
      screen.getByRole("button", { name: "Cancel execution" }),
    ).toBeDisabled();
    expect(
      screen.getByRole("button", { name: "View definition" }),
    ).toBeEnabled();
    expect(
      screen.getByRole("button", { name: "Start new execution" }),
    ).toBeEnabled();
  });

  it("renders stored comparisons, selected details and five timing triplets without modifying raw statistics", async () => {
    const api = apiFixture();
    const workspace = new WorkspaceModel([], [], api);
    const document = workspace.createStudyDraft();
    const model = new StudyExecutionModel(
      "execution-1",
      document.id,
      api,
      status("succeeded"),
    );
    model.result = result;
    model.view = "results";
    document.tab = "executions";
    document.executionModels = [model];
    document.selectedExecutionId = model.executionId;
    render(FinalResults, { model });
    expect(
      screen.getByText(/Negative mission-impact differences/),
    ).toBeInTheDocument();
    await fireEvent.click(screen.getByRole("radio", { name: /small/ }));
    await waitFor(() =>
      expect(screen.getByText(/Warnings: empty_inversion/)).toBeInTheDocument(),
    );
    expect(document.selectedRow?.raw_p_value).toBe(0.0123456789123);
    model.presentation.tier = "large";
    expect(document.selectedRow).toBeNull();
    model.presentation.tier = "all";
    document.tab = "definition";
    expect(document.selectedRow).toBeNull();
    document.tab = "executions";
    expect(document.selectedRow?.raw_p_value).toBe(0.0123456789123);
    await fireEvent.click(screen.getByRole("tab", { name: "Timing" }));
    expect(
      screen.getByRole("heading", { name: "Five measured replicas" }),
    ).toBeInTheDocument();
    expect(screen.getByText(/Warm-up is excluded/)).toBeInTheDocument();
    model.presentation.unit = "ms";
    await tick();
    expect(screen.getAllByText("1.002000 ms")).toHaveLength(2);
    expect(screen.getAllByText("3.008000 ms")).toHaveLength(2);
    expect(document.selectedRow).toBeNull();
    expect(model.result.comparisons[0].estimate).toBe(-0.123456789123);
  });
});
