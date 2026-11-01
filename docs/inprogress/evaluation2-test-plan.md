# Evaluation2 behavior and statistical test plan

> Retained behavior and statistical verification contract.
> The [stable verification record](../history/evaluation2-verification.md) and [calibration report](../history/evaluation2-calibration-20261031.md) record the completed native, calibration and retirement checks.
> Read with the [refactor sketches](evaluation2-refactor-sketches.md), [coordination decisions](grilling-evaluation2-gust-coordination.md), and prototype review policy.

## Acceptance priorities

1. The statistical methodology is sound for its stated assumptions and supported regime.
2. A real study completes the supported lifecycle with correct evidence and durable identity.
3. Focused tests protect observable behavior and catch meaningful regressions.
4. The implementation and tests remain simple enough to maintain.

The latest user instructions permit and require permanent unit/integration tests. Earlier exclusions are superseded. Exact legacy numerical values, NumPy random streams, and old input formats are not compatibility targets.

## Layer selection

```text
Unit tests
  → pure numerical, planning, sampling, and decision behavior

Integration tests
  → persistence, artifact binding, lifecycle, effect ownership, and durable reads

Manual/backend end-to-end study
  → actual application, Gust, optimization, simulation, approval, and final result

Code and test review
  → methodology, ownership, design conformance, and assertion quality
```

Every concern has named cases below. One case may use a small parameter table. These IDs are not instructions to create a test file, fixture framework, or test at every layer for each row.

Use the natural production boundary. If a phase service reads stored context, an integration test is preferable to a new test-only API or dependency-injection framework. Use the existing ExUnit and database-test conventions where practical. Tag automated cases with their type and case ID.

Use TDD for changed behavior: write the intended failing regression test, implement, and rerun the focused cases. Tests for already-correct foundation behavior may pass initially; do not manufacture a failure. Prefer an independent test author within the single implementation assignment when delegation is available. Otherwise use this independently specified plan and the mandatory independent test-implementation review.

## Cases by concern

### Definition and construction

| ID | Primary layer | Requirement and observable result |
|---|---|---|
| INPUT-01 | Unit | WHEN known fields are valid and extra keys are present, THE input boundary SHALL retain the known values, drop extras, and reject missing/invalid required values with bounded errors. |
| INPUT-02 | Integration | WHEN graph inputs are resolved, THE revision constructor SHALL freeze the selected revision and Host foothold; missing graphs, wrong membership, and non-Host footholds SHALL fail before revision insertion. |
| INPUT-03 | Integration | WHEN a different definition is submitted under an already frozen study/revision identity, THE system SHALL preserve the original definition and return a conflict. |
| MODEL-01 | Unit | WHEN candidates, extras, budgets, and alternatives are declared, THE model SHALL derive pool dimensions, canonical comparison order, and unique strategy groups without an independent comparison or absolute-capacity declaration. |
| POLICY-01 | Unit or integration at the normal constructor | WHEN strategy requests are constructed, THEY SHALL inherit the shared simulation and feasibility policy, use permitted supported actions, and include scoring only for scored variants; unusable permission/scoring declarations SHALL be rejected. |

### Randomness and numerical behavior

| ID | Primary layer | Requirement and observable result |
|---|---|---|
| RNG-01 | Unit | WHEN the same scientific context and study seed are used repeatedly, THE allocator SHALL return the same schedules and preserve required Pilot/Final and role separation. |
| RNG-02 | Unit plus collection integration | WHEN execution IDs, timing-replica coordinates, or declaration order change without changing logical scientific identity, THE relevant stream SHALL retain its identity; measured replicas SHALL repeat scientific seeds while owning fresh effects. |
| NUM-01 | Unit | WHEN crossed matrices are analyzed, THE kernel SHALL cover each cell once with disjoint-input matchings and match hand-derived capital/p-value arithmetic. Include rectangular matrices in both orientations, arithmetic capital averaging, and constant columns that add no artificial independent evidence. |
| NUM-02 | Unit | WHEN Pilot outer samples are drawn, THE sampler SHALL use outcome-independent without-replacement indices, keep shared stochastic row inputs together, align attack columns, and share the intended permutation prefixes across candidate sizes. |
| NUM-03 | Unit | WHEN intervals, guard quantiles, or runtime medians are calculated, THE result SHALL use monotone conservative interval brackets and the documented quantile/median rules. Include hand-calculated examples and closed interval/inclusive test boundaries. |
| NUM-04 | Unit | WHEN a null or degenerate sample is analyzed, THE output SHALL follow the reviewed p-value and uncertainty rules without treating empirical zero spread as population certainty. Include missed rare variation, nonzero empirical degeneracy, genuine deterministic equality, and near-zero behavior. Use no add-one tail estimate. |
| NUM-05 | Unit | WHEN native analysis repeats or data/model bounds are consistently rescaled, THE results SHALL preserve repeatability and scale behavior within float64 tolerances; non-boundary p-values/decisions SHALL remain consistent. No former Python stream is required. |
| NUM-06 | Unit / construction boundary | WHEN scientific outcome bounds are constructed or observations are assembled, THE system SHALL use finite frozen-model bounds and reject invalid/out-of-range inputs. Observed sample minima/maxima SHALL NOT substitute for model bounds; structural zero range SHALL be handled explicitly. |
| HOLM-01 | Unit | WHEN a complete family is corrected, THE output SHALL preserve family membership/order and the reviewed inclusive alpha decision with decimal-safe arithmetic; float results SHALL imply the same decision. Include ties, capping, and a decimal-boundary example. |

Q141 selects matching-based bounded-mean betting; no bootstrap/add-one or old five-plan/ten-attack eligibility rule remains. Protect past-only bets separately for each matching. Never use the current observation or another matching's data in a bet. Check graph-derived range/finite inputs, structural zero range, mean-direction conservatism, and empty-interval fallback at their natural boundaries.

Expected numerical values must come from hand calculation, an independent reference, or a clearly justified oracle. Do not calculate the expectation by calling the implementation under test. No exact legacy-output fixtures are required. If the statistical review changes a baseline rule, update its case and rationale before coding it.

### Pilot and physical collection

| ID | Primary layer | Requirement and observable result |
|---|---|---|
| PILOT-01 | Unit or phase-service integration | WHEN candidate assessments are aggregated, THE decision SHALL use every declared comparison, reject incomplete/duplicate fan-in, and apply the reviewed guarded interval-size criterion at the same confidence level as Final. |
| PILOT-02 | Unit or phase-service integration | WHEN several candidates pass, THE selector SHALL use the agreed runtime heuristic and tie-breaks; WHEN none pass, IT SHALL return insufficient. Runtime group counts SHALL include the reference once per budget. |
| COL-01 | Integration | WHEN a replica plan is materialized, THE system SHALL create one physical row per strategy-group/plan coordinate, and logical comparisons SHALL project the single shared CVSS group. |
| COL-02 | Integration | WHEN an item is prepared, reserved, or retried repeatedly, IT SHALL keep its canonical optimization and experiment links rather than create replacement effects. |
| COL-03 | Integration | WHEN a new timing replica or phase collects the same scientific configuration, IT SHALL own fresh item/effect records; no physical effect SHALL be linked into multiple item rows. |
| COL-04 | Integration | WHEN evidence is assembled, IT SHALL contain complete, ordered, correctly bound matrices and attack columns; missing, mismatched, or incomplete source observations SHALL fail at assembly. |

A shared reference can make family members dependent. The method must preserve dependence across comparisons and use independent pairs within each matching; Pilot planning subsets must preserve the declared row/column coupling. Tests must protect the reviewed scientific design rather than assume the old independence claims are correct.

### Workflow, persistence, and public behavior

| ID | Primary layer | Requirement and observable result |
|---|---|---|
| BIND-01 | Integration | WHEN provisioning or continuation is repeated, THE phase SHALL retain one canonical linked Gust run and dispatch that run without duplicating its work. |
| BIND-02 | Integration | IF completion proof names another phase/tier, lacks a unique succeeded terminal task, or cannot decode, THEN THE workflow SHALL reject acceptance without advancing the execution. |
| FLOW-01 | Integration | WHEN Pilot completes, THE execution SHALL pause at awaiting_final and expose the full Pilot report while retaining only the required compact lifecycle outcome. |
| FLOW-02 | Integration | WHEN Final is approved, THE system SHALL freeze the declared candidate/counts; invalid approval SHALL leave the gate unchanged, and insufficient override SHALL require explicit intent. |
| FLOW-03 | Integration | WHEN a continuation wait times out, THE API SHALL return current Status without failing or cancelling the study. Use controlled active work rather than wall-clock timing assertions. |
| FLOW-04 | Integration | WHILE an execution is cancelled, late valid completion SHALL leave it cancelled and SHALL NOT create successor work; a blocked continuation SHALL observe cancellation even without a same-process notification. |
| FLOW-05 | Integration | WHEN Final analysis is accepted, THE result and succeeded state SHALL become durable together; rejected acceptance SHALL preserve prior state, and repeated accepted completion SHALL not create another result. |
| RESULT-01 | Integration | WHEN result/report APIs are called, THEY SHALL return correctly joined typed values for the owning execution and bounded unavailable results before their supported boundary. |

Use actual persistence and Gust artifact stores for integration cases. External optimization/simulation effects may be controlled at an existing boundary for focused scenarios; do not call those cases a real full-study run. Do not test SQL lock strings, private helper invocation counts, or Ecto internals.

### Timing, replicas, and commands

| ID | Primary layer | Requirement and observable result |
|---|---|---|
| TIME-01 | Unit | WHEN ordered boundary readings are summarized, THE result SHALL contain correct plan, simulation, and total durations for five measured replicas, excluding warm-up; invalid boundary sequences SHALL fail. |
| TIME-02 | Integration | WHEN a tier has completed and timings are stored, THE completion reader SHALL reconstruct valid durations without the original clock process. |
| TIME-03 | Domain/service test plus manual interruption | WHEN an incomplete tier loses its clock session, later markers SHALL fail and the workflow SHALL not manufacture a completed measurement or replacement replica. |
| TIME-04 | Unit plus one acceptance integration | WHEN measured replicas differ only in physical execution/output artifact IDs or timing, equality SHALL pass; WHEN frozen scientific inputs, selected actions, or required scientific outcomes differ, equality SHALL fail. |
| CMD-01 | Manual/backend E2E | WHEN a real new-format study is created, run through Pilot, explicitly approved, and continued, THE system SHALL complete all tiers and expose a persisted native Final result. Record whether approval was recommended or an explicit insufficient override. |
| CMD-02 | Manual or focused command integration | WHEN commands start the application, execution commands SHALL have Gust workers, inspection SHALL remain observational, and timing SHALL remain domain-owned. Misconfigured execution roles SHALL produce a useful failure rather than a silent non-executing command. |
| SETUP-01 | Integration/bootstrap smoke | WHEN the standard setup path initializes its approved local target, BOTH application and Gust schemas SHALL exist before seeding, and seeded graphs SHALL be usable for revision construction. |

Do not assert generated UUID values or migration counts. Physical IDs are expected to differ between runs. Preserve meaningful identity such as the frozen input graph, action targets, sample configuration, and seed schedule; do not erase all identifiers indiscriminately from scientific equality.

### Scientific validity, cleanup, and review

| ID | Primary layer | Requirement and observable result |
|---|---|---|
| STAT-01 | Independent statistical/design review | BEFORE accepting the method, THE review SHALL state the estimand, experimental units, row/column dependence, interval/null construction, Pilot selection role, and conditions required by family correction. |
| STAT-02 | Reproducible offline calibration | WHEN the method is exercised on prespecified known-null and known-effect crossed-data models, THE report SHALL estimate relevant error/coverage behavior with Monte Carlo uncertainty and assess it against criteria declared before the results. |
| CLEAN-01 | Deletion audit and code review | WHEN retirement is complete, THE active project SHALL contain no obsolete legacy/Python implementation files, live references, aliases, stubs, fallbacks, service-only bindings/dependencies, or retired build/DAG artifacts. The obsolete implementation MUST BE DELETED; retained native/shared infrastructure and input schema SHALL still work. |
| PERF-01 | Manual measurement | WHEN representative native analysis work is profiled, THE report SHALL state dimensions, repetitions, runtime, and backend so EXLA is added only for an observed need. Avoid fragile speed assertions in unit tests. |
| REVIEW-01 | Independent code/test review | WHEN the batch is reviewed, THE reviewer SHALL check implementation and test assertions against the design, plan, and method, separating material gaps from optional hardening. |

Use the [prespecified statistical checks](evaluation2-statistical-checks.md) for the selected method. Its model equations, fixed seed, dataset counts, diagnostic error flags and Pilot/family experiments were declared before results. The stable calibration report records the complete execution.

Calibration is a scientific validation activity, not a default slow randomized unit test. Use fixed experiment seeds and report dataset counts, matching horizons, numerical settings, assumptions, uncertainty and limitations. Cover the relevant row-dominated, column-dominated, interaction/skew, and shared-reference cases without building a general simulation platform.

Known-null rejection, interval coverage, and family error behavior require statistical interpretation. A single p-value or a tiny noisy rejection-rate sample is not a validity proof. Do not tune acceptance bands after inspecting the result. If a supported regime fails calibration, correct/restrict the method and document why.

The baseline already has executed null counterexamples in [statistical validation](evaluation2-statistical-validation.md). Use them as cases against false certainty, not as expected legacy outputs. Calibration must also cover small/larger counts, rare/skew outcomes, deterministic CVSS rows, pure interactions, shared-column cancellation, shared-reference and partial-null families, complete Pilot selection, insufficient override, and precision on fresh Final evidence. If Monte Carlo p-values remain, assess their precision at the relevant Holm thresholds. The Pilot guard quantile alone is not a fresh-sample precision guarantee.

## Two worked cases

```text
ID: COL-01
Type: Integration
Requirement: WHEN two alternatives share a tier and budget, THE collector SHALL
             execute one CVSS group and project it into both comparisons.
Preconditions: A valid frozen definition and a materialized replica plan.
Action: Prepare its items and assemble the comparison view.
Expected: Unique physical group rows; both comparisons point to the same reference
          group; each physical item retains unique effect ownership.
```

```text
ID: TIME-04
Type: Unit / acceptance integration
Requirement: IF required scientific outcomes differ, THEN replica acceptance
             SHALL fail even when the reported mean mission impact is unchanged.
Preconditions: Five otherwise matching measured scientific summaries.
Action: Change one required flow/capability outcome in one replica.
Expected: Equality fails. A separate variant changing only execution IDs/timing
          passes. Frozen input identity remains meaningful.
```

## Reviewer checklist

- Does each concern have a case or an explicit manual/review validation step?
- Would a plausible wrong implementation fail the assertions?
- Do expectations come from the design/method rather than observed implementation output?
- Do integration cases use real dependencies at the boundary they claim to cover?
- Do controlled effects stay at external boundaries instead of mocking the behavior being tested?
- Are fixtures small and reusable without a custom fixture language or production test hooks?
- Are tests deterministic, independent, and free of arbitrary sleeps or machine-speed assumptions?
- Are statistical calibration results interpreted with uncertainty and stated assumptions?
- Are old-format/NumPy compatibility assertions absent unless they protect a still-required scientific property?
- Does the final manual study exercise actual optimization/simulation and persisted result reads?

Coverage tools can expose gaps; a blanket percentage target is not the acceptance criterion. Do not add a test for each private function merely to increase coverage.

## Database and execution boundary

The earlier completed reset applied only to `network_defense_dev`. It did not establish an automated test database.

Q140 now explicitly permits creation/use of local `network_defense_test` in the existing PostgreSQL instance. Verify local host/port, credentials, database name, and both Repo targets before setup. Use existing SQL sandbox conventions where compatible with the integration boundary. Preserve development data and seeded graphs; the real manual study remains on development. No database was created during design.

Implement the refactor and tests through the dependency-ordered goals, with one owner and 1–2 scaffolding workers per goal. Independent review includes test implementation. This plan records the pre-implementation contract; the stable verification records now document completed execution. Database permission remains bounded by the local targets above.
