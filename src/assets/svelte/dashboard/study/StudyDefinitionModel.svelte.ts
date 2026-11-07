import { stringify } from "yaml";
import type {
  Definition,
  DefinitionInput,
  DefinitionOptions,
  Issue,
  Error as StudyError,
} from "../../contracts.generated/dashboard/study";
import { draftFromDefinition, newDraft, type StudyDraft } from "./types";

export class StudyDefinitionModel {
  draft = $state<StudyDraft>(newDraft());
  options = $state.raw<DefinitionOptions | null>(null);
  error = $state.raw<StudyError | null>(null);
  freezing = $state(false);

  constructor(definition?: Definition) {
    if (definition) this.draft = draftFromDefinition(definition);
  }

  fieldError(...path: (string | number)[]): string {
    const key = path.join(".");
    return (
      this.error?.issues
        .filter((issue) => this.issueField(issue.path) === key)
        .map((issue) => issue.message)
        .join("\n") ?? ""
    );
  }

  get formError(): StudyError | null {
    if (!this.error) return null;
    const fields = this.fieldPaths();
    const issues = this.error.issues.filter(
      (issue) => !fields.includes(this.issueField(issue.path)),
    );
    return issues.length ? { ...this.error, issues } : null;
  }

  private fieldPaths(): string[] {
    const fields = Object.entries(this.draft)
      .filter(([, value]) => typeof value === "string")
      .map(([key]) => key);
    fields.push("allowed_action_types", "rules", "candidates");
    this.draft.candidates.forEach((candidate, index) =>
      Object.keys(candidate).forEach((field) =>
        fields.push(`candidates.${index}.${field}`),
      ),
    );
    if (this.options) {
      fields.push("tiers");
      this.draft.tiers.forEach((tier, index) => {
        const prefix = `tiers.${index}`;
        for (const field of [
          "graph_revision_id",
          "foothold_node_id",
          "budgets",
          "alternatives",
        ])
          fields.push(`${prefix}.${field}`);
        tier.budgets.forEach((_, budget) =>
          fields.push(`${prefix}.budgets.${budget}`),
        );
        tier.alternatives.forEach((alternative, position) => {
          const base = `${prefix}.alternatives.${position}`;
          fields.push(`${base}.strategy`);
          if (
            this.options?.alternatives.find(
              (item) => item.value === alternative.strategy,
            )?.scoring_required
          )
            fields.push(`${base}.objective`, `${base}.monte_carlo_trials`);
        });
      });
    }
    return fields;
  }

  private issueField(input: Issue["path"]): string {
    let path = input[0] === "definition" ? input.slice(1) : [...input];
    const aliases: Record<string, string> = {
      "study.id": "study_id",
      "study.revision": "revision",
      "family.id": "family_id",
      "family.alpha": "family_alpha",
      "analysis.confidence_level": "confidence_level",
      "defense.feasibility": "feasibility",
      "defense.allowed_action_types": "allowed_action_types",
      "simulation.iterations_per_run": "iterations_per_run",
      "simulation.max_attempts": "max_attempts",
      "simulation.rules": "rules",
      "pilot.candidates": "candidates",
      "pilot.extra_pool.plans": "extra_pool_plans",
      "pilot.extra_pool.attacks": "extra_pool_attacks",
      "pilot.precision.outer_subsamples": "outer_subsamples",
      "pilot.precision.target_half_width": "target_half_width",
      "pilot.precision.guard_quantile": "guard_quantile",
    };
    for (const [prefix, field] of Object.entries(aliases)) {
      const parts = prefix.split(".");
      if (parts.every((part, index) => path[index] === part)) {
        path = [field, ...path.slice(parts.length)];
        break;
      }
    }
    if (path[0] === "rules" || path[0] === "allowed_action_types")
      return String(path[0]);
    if (path[0] === "tiers" && typeof path[1] === "string") {
      const index = this.draft.tiers.findIndex((tier) => tier.tier === path[1]);
      if (index >= 0) path[1] = index;
    }
    if (
      path[0] === "tiers" &&
      path[2] === "alternatives" &&
      path[4] === "scoring"
    )
      path.splice(4, 1);
    return path.join(".");
  }

  get yaml(): string {
    return stringify(this.declaration(), { lineWidth: 0 });
  }

  // Preview formatting leaves submission values unchanged.
  declaration(): Record<string, unknown> {
    const d = this.draft;
    const n = (v: string) =>
      v.trim() === "" ? null : Number.isFinite(Number(v)) ? Number(v) : v;
    return {
      study: { id: d.study_id, revision: n(d.revision) },
      seed: /^\d+$/.test(d.seed) ? BigInt(d.seed) : d.seed,
      family: { id: d.family_id, alpha: n(d.family_alpha) },
      analysis: { confidence_level: n(d.confidence_level) },
      defense: {
        feasibility: d.feasibility,
        allowed_action_types: [...d.allowed_action_types],
      },
      simulation: {
        iterations_per_run: n(d.iterations_per_run),
        max_attempts: n(d.max_attempts),
        rules: [...d.rules],
      },
      tiers: Object.fromEntries(
        d.tiers.map((t) => [
          t.tier,
          {
            graph_revision_id: t.graph_revision_id,
            foothold_node_id: t.foothold_node_id,
            budgets: t.budgets.map(n),
            alternatives: t.alternatives.map((a) => ({
              strategy: a.strategy,
              ...(a.objective
                ? {
                    scoring: {
                      objective: a.objective,
                      monte_carlo_trials: n(a.monte_carlo_trials),
                    },
                  }
                : {}),
            })),
          },
        ]),
      ),
      pilot: {
        candidates: d.candidates.map((c) => ({
          id: c.id,
          plans: n(c.plans),
          attacks: n(c.attacks),
        })),
        extra_pool: {
          plans: n(d.extra_pool_plans),
          attacks: n(d.extra_pool_attacks),
        },
        precision: {
          outer_subsamples: n(d.outer_subsamples),
          target_half_width: n(d.target_half_width),
          guard_quantile: n(d.guard_quantile),
        },
      },
    };
  }

  /** The backend casts and validates the unchanged form values. */
  toWire(): DefinitionInput {
    const d = this.draft;
    return {
      ...d,
      allowed_action_types: [...d.allowed_action_types],
      rules: [...d.rules],
      tiers: d.tiers.map((t) => ({
        ...t,
        budgets: [...t.budgets],
        alternatives: t.alternatives.map((a) => ({
          strategy: a.strategy,
          objective: a.objective || null,
          monte_carlo_trials: a.monte_carlo_trials || null,
        })),
      })),
      candidates: d.candidates.map((candidate) => ({ ...candidate })),
    };
  }
}
