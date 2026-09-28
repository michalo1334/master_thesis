import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/svelte";
import ImportedStudyResults from "./ImportedStudyResults.svelte";
import type { EvaluationAnalysis } from "../../contracts.generated/dashboard/evaluation";
import { ImportedStudyResultsDocument } from "./ImportedStudyResultsDocument.svelte";

afterEach(cleanup);

function analysis(mode: "study-pilot" | "study-analyze"): EvaluationAnalysis {
  return {
    capability_results: [],
    feasibility_summary: [],
    metadata: {
      command_mode: mode,
      family_scope: "study",
      family_size: 1,
      schema_version: 1,
      runtime_summary: {
        median_plan_selection_runtime_ms: 50,
        median_simulation_runtime_ms: 100,
        evaluator_runtime_ms: 150,
      },
      ...(mode === "study-pilot"
        ? {
            recommended_plan_selection_seed_count: 4,
            recommended_attacks_per_plan: 10,
            insufficient_pilot: false,
          }
        : {}),
    },
    pilot_results:
      mode === "study-pilot"
        ? [
            {
              comparison_id: "small-comparison",
              tier: "small",
              informative: true,
              candidate_plan_count: 4,
              candidate_attacks_per_plan: 10,
              guarded_ci_half_width: 0.5,
              target: 1,
              passes: true,
            },
          ]
        : [],
    primary_results:
      mode === "study-analyze"
        ? [
            {
              comparison: -0.5,
              comparison_id: "small-comparison",
              tier: "small",
              strategy: "simulation_informed",
              model_variant: "full",
              baseline: "cvss",
              baseline_model_variant: "full",
              budget: 1,
              outcome: "mission_impact",
              informative: true,
              tested_plan_count: 4,
              baseline_plan_count: 4,
              attacks_per_plan: 10,
            },
          ]
        : [],
    secondary_results: [],
  };
}

describe("ImportedStudyResults", () => {
  it("renders a read-only pilot study result", () => {
    render(ImportedStudyResults, {
      props: {
        document: new ImportedStudyResultsDocument(analysis("study-pilot")),
      },
    });

    expect(
      screen.getByRole("heading", { name: "Pilot planning results" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("status")).toHaveTextContent(
      "Pilot planning output",
    );
    expect(
      screen.getByRole("columnheader", { name: "Guarded half-width" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /run|cancel|download/i }),
    ).not.toBeInTheDocument();
  });

  it("renders a read-only final study result", () => {
    render(ImportedStudyResults, {
      props: {
        document: new ImportedStudyResultsDocument(analysis("study-analyze")),
      },
    });

    expect(
      screen.getByRole("heading", { name: "Final analysis" }),
    ).toBeInTheDocument();
    expect(screen.getByText("simulation_informed (full)")).toBeInTheDocument();
    expect(
      screen.getByRole("columnheader", { name: "Tested plans" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /run|cancel|download/i }),
    ).not.toBeInTheDocument();
  });
});
