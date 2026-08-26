# Phase 3 Domain Model and Logging Remediation

## Design

Phase 3 has three fixed model variants. Each variant defines one objective and
one pre-attack feasibility rule. Manifests can declare any non-empty subset of
the variants, but each declaration must match the canonical definition.

| Domain value | Wire and database value | Objective | Pre-attack feasibility |
| --- | --- | --- | --- |
| `:full` | `full` | Mission impact, then blast radius | Required |
| `:blast_only_unconstrained` | `blast_only_unconstrained` | Blast radius only | Not required |
| `:mission_only` | `mission_only` | Mission impact only | Required |

Elixir uses atoms after manifest validation. JSON, PostgreSQL, Python, and
TypeScript use the same underscore strings.

`NetworkDefense.Optimization.ModelVariant` owns model-variant definitions and
their settings. `SimulationObjective` owns the objective enum and wire
conversion. `OptimizationRun.model_variant` uses `Ecto.Enum` over the existing
string column. A database constraint limits non-null values to the three wire
values.

The manifest keeps explicit objective and feasibility fields for readable,
self-describing artifacts. Validation requires these fields to match the
selected variant. Runtime and export code derive settings from the canonical
domain definition. This removes the private output-contract variant index.

Debug logs keep flat event, correlation, and primary identifier fields. They
also carry sanitized nested domain objects. `LogValue.normalize/1` uses
object-specific `Map.take/2` allowlists for evaluation runs, optimization runs,
experiments, graphs, and optimization requests. It does not serialize Ecto
associations, resolved manifests, graph internals, or other unbounded fields.

`MissionImpact.pre_attack_feasible?/1` remains the single feasibility
implementation. `SimulationObjective` only owns ranking behavior.

### Tests

- **When** a manifest declares a known variant with its canonical settings,
  **the system shall** accept it and convert its identifier and objective to
  domain atoms for execution.
- **When** a manifest changes one setting of a known variant, **the system
  shall** reject the declaration at that variant's field path.
- **When** a manifest declares an unknown variant, **the system shall** reject
  it without creating an atom.
- **When** an evaluation plan is persisted and reloaded, **the system shall**
  retain its domain variant and mapped database value.
- **When** an evaluation archive is generated, **the system shall** write the
  canonical variant, objective, and feasibility wire values.
- **When** each objective ranks conflicting outcomes, **the system shall** use
  its declared ordering.
- **When** feasibility is required, **the optimizer shall** use the canonical
  mission-impact feasibility check.
- **When** a domain object is logged, **the formatter shall** include its
  allowlisted fields and omit associations, resolved manifests, actions, runs,
  and graph indexes.

## Execution

### Phase 1: Domain and Contracts

1. Add fixed model-variant and objective conversions with precise atom types.
2. Validate canonical variant definitions in the Elixir manifest contract.
3. Convert evaluation plan identities and strategy settings at the validated
   boundary.
4. Use atoms in simulation-backed strategies and remove the duplicate
   feasibility function.
5. Map `OptimizationRun.model_variant` through `Ecto.Enum` and add the database
   constraint.
6. Derive exported plan settings from the domain variant and remove the private
   manifest index.
7. Mirror fixed variant validation in Python analysis.
8. Add model-variant enum metadata to dashboard contracts and regenerate the
   TypeScript contracts.
9. Update fixtures, tests, defaults, and Phase 3 documentation for the three
   canonical variants.

### Phase 2: Logging and Integration

1. Add object-specific allowlist normalization for evaluation runs,
   optimization runs, experiments, graphs, and optimization requests.
2. Refactor logs in `evaluator.ex`, `output_contract.ex`, and
   `optimizations.ex` to include nested sanitized objects while retaining flat
   event, correlation, and identifier fields.
3. Pass the graph to plan logging and add event names to inline optimization
   errors.
4. Add focused normalization and emitted-log checks.
5. Review the complete diff for contract drift, unsafe atom conversion, and
   unrelated worktree changes.
6. Run focused and full verification through `cmd_runner`, including Elixir,
   Python, generated contracts, Svelte checks when applicable, static analysis,
   and `git diff --check`.

Do not modify or revert unrelated worktree changes. Do not add compatibility
for schema version 2 or historical database rows.
