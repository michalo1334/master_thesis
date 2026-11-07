import { vi } from "vitest";
import { studyTiers } from "../../contracts.generated/dashboard/study";
import type { DashboardApi } from "../dashboard-api";
import type {
  Definition,
  DefinitionOptions,
  PilotResult,
  Reply,
  Result,
  Status,
  PilotOutcome,
} from "../../contracts.generated/dashboard/study";
export const definition: Definition = {
  study_id: "browser-test",
  revision: 1,
  seed: "9007199254740993",
  family_id: "family",
  family_alpha: 0.05,
  confidence_level: 0.95,
  feasibility: "unrestricted",
  allowed_action_types: ["patch_vulnerability"],
  iterations_per_run: 2,
  max_attempts: 1,
  rules: ["remote_service_exploitation"],
  tiers: studyTiers.map((tier, index) => ({
    tier,
    graph_revision_id: `graph-${index}`,
    foothold_node_id: `host-${index}`,
    budgets: [1],
    alternatives: [
      { strategy: "random", objective: null, monte_carlo_trials: null },
    ],
  })),
  candidates: [{ id: "tiny", plans: 1, attacks: 2 }],
  extra_pool_plans: 0,
  extra_pool_attacks: 0,
  outer_subsamples: 2,
  target_half_width: 0.5,
  guard_quantile: 0.9,
};
export const options: DefinitionOptions = {
  actions: ["patch_vulnerability"],
  rules: ["remote_service_exploitation"],
  alternatives: [
    {
      value: "random",
      scoring_required: false,
      action_types: ["patch_vulnerability"],
    },
  ],
  objectives: ["mission_impact_only"],
  measurement_label: "test-fixture-only",
};
export const status = (
  state: Status["state"] = "collecting_pilot",
): Status => ({
  execution_id: "execution-1",
  revision: { study_id: definition.study_id, revision: 1 },
  state,
  pilot_outcome: null,
  selection: null,
  error: null,
});
export const pilot = (
  outcome: PilotOutcome["outcome"] = "insufficient",
): PilotResult => ({
  method: "precision_pilot_v1",
  selection_rule: "lowest_predicted_runtime",
  outcome: {
    outcome,
    ...(outcome === "recommended"
      ? { candidate_id: "tiny", plan_count_per_side: 1, attacks_per_plan: 2 }
      : {}),
  },
  candidates: [
    {
      id: "tiny",
      plan_count_per_side: 1,
      attacks_per_plan: 2,
      predicted_runtime_ms: 1.25,
      worst_guarded_half_width: 0.123456789123,
      passes: outcome === "recommended",
      comparisons: [
        {
          identity: {
            tier: "small",
            budget: 1,
            alternative: "random",
            reference: "cvss",
            outcome: "mission_impact",
          },
          guarded_half_width: 0.123456789123,
          informative: true,
          passes: outcome === "recommended",
        },
      ],
    },
  ],
});
export const result: Result = {
  execution_id: "execution-1",
  revision: { study_id: definition.study_id, revision: 1 },
  pilot_outcome: pilot().outcome,
  selection: {
    candidate_id: "tiny",
    plan_count_per_side: 1,
    attacks_per_plan: 2,
  },
  family_id: "family",
  family_method: "holm",
  family_alpha: 0.05,
  comparisons: [
    {
      identity: {
        tier: "small",
        budget: 1,
        alternative: "random",
        reference: "cvss",
        outcome: "mission_impact",
      },
      method: "matching_bounded_mean_v1",
      contrast: "alternative_minus_reference",
      estimate: -0.123456789123,
      confidence_level: 0.95,
      lower: -0.45,
      upper: 0.01,
      test_method: "sign_conservative_betting",
      test_alternative: "two_sided",
      raw_p_value: 0.0123456789123,
      adjusted_p_value: 0.0370370367369,
      reject_null: true,
      assessment: "informative",
      warnings: ["empty_inversion"],
    },
  ],
  timing: studyTiers.map((tier) => ({
    tier,
    replicas: Array.from({ length: 5 }, (_, position) => ({
      position,
      plan_selection_us: 1000 + position,
      simulation_us: 2000 + position,
      total_us: 3000 + 2 * position,
    })),
    summaries: [
      {
        boundary: "plan_selection",
        median_us: 1002,
        minimum_us: 1000,
        maximum_us: 1004,
      },
      {
        boundary: "simulation",
        median_us: 2002,
        minimum_us: 2000,
        maximum_us: 2004,
      },
      {
        boundary: "total",
        median_us: 3004,
        minimum_us: 3000,
        maximum_us: 3008,
      },
    ],
  })),
};
export function reply(values: Partial<Reply> = {}): Reply {
  return { status: "ok", revisions: [], executions: [], ...values };
}
export function apiFixture(
  handler?: (
    event: string,
    payload: any,
  ) => Partial<Reply> | Promise<Partial<Reply>>,
) {
  const studyRequest = vi.fn(async (event, payload = {}) =>
    reply(
      handler
        ? await handler(event, payload)
        : event === "fetch_study_options"
          ? { options }
          : event === "fetch_study_status"
            ? { execution: status() }
            : {},
    ),
  );
  return {
    studyRequest,
    openGraph: vi
      .fn()
      .mockResolvedValue({ status: "ok", graph: { nodes: [] } }),
  } as unknown as DashboardApi & { studyRequest: typeof studyRequest };
}
