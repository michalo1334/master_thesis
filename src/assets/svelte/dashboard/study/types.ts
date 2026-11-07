import {
  studyTiers,
  type Definition,
  type Vocabulary,
} from "../../contracts.generated/dashboard/study";

export type StudyRequestName = Vocabulary["request"];

export type DraftAlternative = {
  strategy: string;
  objective: string;
  monte_carlo_trials: string;
};
export type DraftTier = {
  tier: Vocabulary["tier"];
  graph_revision_id: string;
  foothold_node_id: string;
  budgets: string[];
  alternatives: DraftAlternative[];
};
export type StudyDraft = Omit<
  Definition,
  | "revision"
  | "family_alpha"
  | "confidence_level"
  | "feasibility"
  | "iterations_per_run"
  | "max_attempts"
  | "tiers"
  | "candidates"
  | "extra_pool_plans"
  | "extra_pool_attacks"
  | "outer_subsamples"
  | "target_half_width"
  | "guard_quantile"
> & {
  revision: string;
  family_alpha: string;
  confidence_level: string;
  feasibility: string;
  iterations_per_run: string;
  max_attempts: string;
  tiers: DraftTier[];
  candidates: { id: string; plans: string; attacks: string }[];
  extra_pool_plans: string;
  extra_pool_attacks: string;
  outer_subsamples: string;
  target_half_width: string;
  guard_quantile: string;
};

export function newDraft(): StudyDraft {
  return {
    study_id: "",
    revision: "",
    seed: "",
    family_id: "",
    family_alpha: "",
    confidence_level: "",
    feasibility: "",
    allowed_action_types: [],
    iterations_per_run: "",
    max_attempts: "",
    rules: [],
    tiers: studyTiers.map((tier) => ({
      tier,
      graph_revision_id: "",
      foothold_node_id: "",
      budgets: [""],
      alternatives: [],
    })),
    candidates: [{ id: "", plans: "", attacks: "" }],
    extra_pool_plans: "",
    extra_pool_attacks: "",
    outer_subsamples: "",
    target_half_width: "",
    guard_quantile: "",
  };
}

export function draftFromDefinition(value: Definition): StudyDraft {
  const draft = newDraft();
  for (const key of Object.keys(draft) as (keyof StudyDraft)[]) {
    const field = value[key as keyof Definition];
    if (key === "tiers" || key === "candidates") continue;
    (draft as unknown as Record<string, unknown>)[key] = Array.isArray(field)
      ? [...field]
      : String(field ?? "");
  }
  draft.tiers = value.tiers.map((t) => ({
    ...t,
    budgets: t.budgets.map(String),
    alternatives: t.alternatives.map((a) => ({
      strategy: a.strategy,
      objective: a.objective ?? "",
      monte_carlo_trials:
        a.monte_carlo_trials == null ? "" : String(a.monte_carlo_trials),
    })),
  }));
  draft.candidates = value.candidates.map((c) => ({
    id: c.id,
    plans: String(c.plans),
    attacks: String(c.attacks),
  }));
  return draft;
}

export function isStudyDraft(value: unknown): value is StudyDraft {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  const sample = newDraft();
  return (
    Object.entries(sample).every(([key, field]) =>
      typeof field === "string"
        ? typeof v[key] === "string"
        : Array.isArray(v[key]),
    ) &&
    (v.allowed_action_types as unknown[]).every((x) => typeof x === "string") &&
    (v.rules as unknown[]).every((x) => typeof x === "string") &&
    (v.tiers as unknown[]).length === studyTiers.length &&
    (v.tiers as unknown[]).every((tier, index) => {
      if (!tier || typeof tier !== "object") return false;
      const t = tier as DraftTier;
      return (
        t.tier === studyTiers[index] &&
        typeof t.graph_revision_id === "string" &&
        typeof t.foothold_node_id === "string" &&
        Array.isArray(t.budgets) &&
        t.budgets.every((x) => typeof x === "string") &&
        Array.isArray(t.alternatives) &&
        t.alternatives.every(
          (a) =>
            a !== null &&
            typeof a === "object" &&
            typeof a.strategy === "string" &&
            typeof a.objective === "string" &&
            typeof a.monte_carlo_trials === "string",
        )
      );
    }) &&
    (v.candidates as { id: string; plans: string; attacks: string }[]).every(
      (c) =>
        c !== null &&
        typeof c === "object" &&
        typeof c.id === "string" &&
        typeof c.plans === "string" &&
        typeof c.attacks === "string",
    )
  );
}
