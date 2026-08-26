# Phase 3: Model Comparison

## Design

One manifest defines the complete model-comparison experiment. One evaluation
run uses one immutable source graph and one shared attack-seed schedule. The
result ZIP contains every selected plan and terminal outcome needed for the
declared strategy and model comparisons.

Manifest schema version 3 replaces the singular model configuration with named
model variants. Each strategy run references one model variant. The manifest
lists each intended execution explicitly; the runner does not create an
implicit cross-product.

```json
{
  "schema_version": 3,
  "model_version": "phase-3-model",
  "model_variants": [
    {
      "id": "full",
      "objective": "mission_then_blast_radius",
      "require_pre_attack_feasibility": true
    },
    {
      "id": "blast_only_unconstrained",
      "objective": "blast_radius_only",
      "require_pre_attack_feasibility": false
    }
  ],
  "strategy_runs": [
    {
      "model_variant": "full",
      "strategy": "simulation_informed",
      "budget": 2,
      "selection_seeds": [310, 311]
    },
    {
      "model_variant": "blast_only_unconstrained",
      "strategy": "simulation_informed",
      "budget": 2,
      "selection_seeds": [310, 311]
    }
  ]
}
```

A comparison identifies both plan groups:

```json
{
  "strategy": "simulation_informed",
  "model_variant": "blast_only_unconstrained",
  "baseline": "simulation_informed",
  "baseline_model_variant": "full",
  "budget": 2,
  "outcome": "blast_radius"
}
```

The plan identity is the model variant, strategy, budget, and selection seed.
This identity controls persistence, resume lookup, export ordering, and
analysis grouping.

```mermaid
flowchart LR
    M[Version 3 manifest] --> V[Validate variants, plans, and comparisons]
    V --> G[Load one source graph]
    G --> S[Build one attack-seed schedule]
    S --> P[Select all model-aware plans]
    P --> E[Evaluate every plan with shared attack seeds]
    E --> Z[Write one ZIP]
    Z --> A[Run all declared comparisons]
    A --> R[Tables, figures, and dashboard report]
```

The objectives rank raw expected mission impact and blast radius as follows:

| Objective | Ranking order |
| --- | --- |
| `blast_radius_only` | Blast radius, then cost. |
| `mission_impact_only` | Mission impact, then cost. |
| `mission_then_blast_radius` | Mission impact, blast radius, then cost. |

Feasibility is an independent hard constraint. When it is on, the strategy
does not score infeasible candidates and the optimizer does not apply them.
When it is off, both layers permit the plan. Mission-impact output still
records disruption caused by the defense.

The ZIP keeps the existing files. `manifest.resolved.json` stores the complete
experiment matrix. Each `plans.jsonl` record stores its model variant,
objective, and feasibility rule. Trial, capability, and summary rows continue
to reference the plan by `plan_id`.

The Python analysis uses model-aware plan identities and comparisons. It keeps
model variants separate in paired results, CDFs, plan-selection variation, and
figures. A same-strategy comparison across variants must use matching selection
seeds so the comparison changes only the model.

This is a destructive contract replacement. New manifests and ZIPs must use
schema version 3. The implementation does not retain version 2 execution or
analysis compatibility. The original evaluation migration becomes the
canonical schema and the local database must be reset after the change.

### Checks

- **When** a manifest references an unknown model variant, **the runner shall**
  reject it before it creates execution rows.
- **When** two variants use the same strategy, budget, and selection seed,
  **the runner shall** persist two distinct plans.
- **When** plans belong to one manifest, **the runner shall** evaluate them with
  the same ordered attack seeds.
- **When** a same-strategy cross-model comparison uses different selection
  seeds, **the analysis shall** reject it.
- **When** objectives receive conflicting mission and blast-radius outcomes,
  **each objective shall** use its declared ranking order.
- **When** feasibility is on, **the optimizer shall** reject a required-flow
  cut.
- **When** feasibility is off, **the optimizer shall** permit the same cut and
  report its mission effect.
- **When** an evaluation resumes, **the runner shall not** duplicate plans or
  trials for any model variant.
- **When** one ZIP contains several variants, **the analysis shall** keep their
  result and CDF groups separate.
- **When** the same ZIP is analyzed twice, **the analysis shall** produce
  equivalent machine-readable results.

## Execution

### 1. Manifest And Persistence

Add schema-version-3 model variants and model-aware comparison validation.
Retroactively add `model_variant` to evaluation-owned optimization runs and to
their unique identity. Update fixtures and persistence tests.

Review the manifest references, database constraints, and resume identity
before continuing.

### 2. Objective And Feasibility

Add shared objective ranking to `SimulationObjective`. Pass the selected
objective and feasibility rule through simulation-backed strategies. Make the
optimizer's feasibility boundary configurable while retaining the current
standalone defaults.

Test conflicting objectives and both required-flow feasibility states. Review
annealing best-plan ordering separately from its probabilistic search energy.

### 3. Runner And Export

Expand evaluator plan keys, persistence, resume lookup, progress, telemetry,
and logs with the model variant. Add model metadata to `plans.jsonl` and to the
evaluation report. Keep all plans on the shared attack schedule.

Test model-aware resume safety, export completeness, and deterministic output.

### 4. Statistical Analysis

Parse model-aware identities and comparison selectors. Validate matching
selection seeds for same-strategy cross-model comparisons. Include model
variants in result tables, CDF groups, variation output, metadata, and figures.

Test malformed identities, missing pairs, mixed selection seeds, deterministic
analysis, and HTTP transport of the updated ZIP.

### 5. Dashboard And Documentation

Update analysis-result and dashboard contracts, regenerate TypeScript types,
and display model variants in plan and statistical-result tables. Update the
evaluation roadmap and manifest examples to schema version 3.

Review the report at desktop and mobile widths.

### 6. Verification

Run focused Elixir and Python tests, frontend tests and type checks, and
`mix precommit`. Execute a small two-variant evaluation and verify that its one
ZIP contains distinct plans, paired attack seeds, model-aware analysis rows,
and separate CDF groups.
