import type { DescribeManifestReply } from "../../contracts.generated/dashboard/evaluation";
import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen, within } from "@testing-library/svelte";
import ManifestPreview from "./ManifestPreview.svelte";
afterEach(cleanup);

const content = {
  schema_version: 3,
  source: { type: "topology", generator: "enterprise", hosts: 50, seed: 42 },
  attacker: {
    entry_host: { type: "semantic_key", value: "internet" },
    max_attempts: 1,
  },
  model_variants: [
    {
      id: "full",
      objective: "mission_then_blast_radius",
      require_pre_attack_feasibility: true,
    },
    {
      id: "blast_only",
      objective: "blast_radius_only",
      require_pre_attack_feasibility: false,
    },
  ],
  analysis: {
    confidence_level: 0.95,
    multiplicity_correction: "holm",
    primary_comparisons: [
      {
        strategy: "raw_strategy",
        model_variant: "full",
        baseline: "cvss",
        baseline_model_variant: "full",
        budget: 1,
        outcome: "raw_outcome",
      },
    ],
  },
  evaluation: { trials: 1000, seed: 9001 },
};

const reply: DescribeManifestReply = {
  status: "ok",
  plans: [
    {
      model_variant: "full",
      strategy: "cvss",
      budget: 1,
      selection_seed: 101,
    },
    {
      model_variant: "full",
      strategy: "simulation_informed",
      budget: 1,
      selection_seed: 201,
    },
    {
      model_variant: "full",
      strategy: "simulation_informed",
      budget: 1,
      selection_seed: 202,
    },
  ],
  comparison_groups: [
    {
      index: 0,
      outcome: "blast_radius",
      tested: {
        model_variant: "full",
        strategy: "simulation_informed",
        budget: 1,
        selection_seeds: [201, 202],
      },
      baseline: {
        model_variant: "full",
        strategy: "cvss",
        budget: 1,
        selection_seeds: [101],
      },
    },
  ],
  errors: [],
};

function sectionFor(heading: string): HTMLElement {
  const headingElement = screen.getByText(heading);
  return headingElement.closest("section") as HTMLElement;
}

describe("ManifestPreview", () => {
  it("renders the structured preview of a valid manifest", () => {
    render(ManifestPreview, {
      props: { content, reply, errors: [], isLoading: false },
    });

    const source = within(sectionFor("Source and attacker"));
    expect(source.getByText("enterprise")).toBeInTheDocument();
    expect(source.getByText("internet")).toBeInTheDocument();

    const variants = within(sectionFor("Model variants"));
    expect(variants.getByRole("row", { name: /full/ })).toBeInTheDocument();
    expect(
      variants.getByRole("row", { name: /blast_only/ }),
    ).toBeInTheDocument();

    const plans = within(sectionFor("Planned strategy runs"));
    expect(plans.getAllByRole("row")).toHaveLength(4);
    expect(plans.getByText("101")).toBeInTheDocument();
    expect(plans.getByText("202")).toBeInTheDocument();

    const groups = within(sectionFor("Primary comparisons"));
    expect(groups.getByText("blast_radius")).toBeInTheDocument();
    expect(
      groups.getByText(
        /simulation_informed \(full\), budget 1, seeds 201, 202/,
      ),
    ).toBeInTheDocument();
    expect(
      groups.getByText(/cvss \(full\), budget 1, seeds 101/),
    ).toBeInTheDocument();

    const analysis = within(sectionFor("Analysis settings"));
    expect(analysis.getByText("holm")).toBeInTheDocument();
    expect(analysis.queryByText(/raw_strategy/)).not.toBeInTheDocument();

    const evaluation = within(sectionFor("Evaluation settings"));
    expect(evaluation.getByText("1000")).toBeInTheDocument();
  });

  it("renders only errors for a non-ok reply", () => {
    render(ManifestPreview, {
      props: {
        content,
        reply: {
          status: "invalid_manifest",
          plans: [],
          comparison_groups: [],
          errors: [{ path: "strategy_runs", message: "must not be empty" }],
        },
        errors: [{ path: "strategy_runs", message: "must not be empty" }],
        isLoading: false,
      },
    });

    expect(screen.getByRole("alert")).toHaveTextContent(
      "strategy_runs: must not be empty",
    );
    expect(screen.queryByText("Source and attacker")).not.toBeInTheDocument();
    expect(screen.queryByText("Model variants")).not.toBeInTheDocument();
    expect(screen.queryByText("Planned strategy runs")).not.toBeInTheDocument();
    expect(screen.queryByText("Primary comparisons")).not.toBeInTheDocument();
    expect(screen.queryByText("Analysis settings")).not.toBeInTheDocument();
    expect(screen.queryByText("Evaluation settings")).not.toBeInTheDocument();
  });

  it("renders comparison groups from the server reply instead of raw analysis entries", () => {
    render(ManifestPreview, {
      props: {
        content: {
          ...content,
          analysis: {
            primary_comparisons: [
              {
                strategy: "raw_strategy",
                model_variant: "full",
                baseline: "cvss",
                baseline_model_variant: "full",
                budget: 1,
                outcome: "raw_outcome",
              },
            ],
          },
        },
        reply,
        errors: [],
        isLoading: false,
      },
    });

    const groups = within(sectionFor("Primary comparisons"));
    expect(
      groups.getByText(
        /simulation_informed \(full\), budget 1, seeds 201, 202/,
      ),
    ).toBeInTheDocument();
    expect(groups.getByText("blast_radius")).toBeInTheDocument();
    expect(groups.queryByText("raw_strategy")).not.toBeInTheDocument();
    expect(groups.queryByText("raw_outcome")).not.toBeInTheDocument();
  });

  it("announces a loading state", () => {
    render(ManifestPreview, {
      props: { content: null, reply: null, errors: [], isLoading: true },
    });

    expect(screen.getByRole("status")).toHaveTextContent(
      "Describing manifest…",
    );
  });

  it("renders unavailable states for unusable manifest fields", () => {
    render(ManifestPreview, {
      props: {
        content: {
          source: "junk",
          attacker: 42,
          model_variants: ["not-an-object"],
          analysis: [],
          evaluation: null,
        },
        reply: { status: "ok", plans: [], comparison_groups: [], errors: [] },
        errors: [],
        isLoading: false,
      },
    });

    const source = within(sectionFor("Source and attacker"));
    expect(source.getAllByText("—").length).toBeGreaterThan(0);

    const variants = within(sectionFor("Model variants"));
    expect(variants.getAllByRole("row")).toHaveLength(2);
    expect(variants.getAllByText("—").length).toBeGreaterThan(0);

    expect(screen.getByText("No strategy runs planned.")).toBeInTheDocument();
    expect(
      screen.getByText("No primary comparisons declared."),
    ).toBeInTheDocument();
    expect(
      screen.getByText("No analysis settings declared."),
    ).toBeInTheDocument();
    expect(
      screen.getByText("No evaluation settings declared."),
    ).toBeInTheDocument();
  });
});
