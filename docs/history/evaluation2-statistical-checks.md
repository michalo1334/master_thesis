# Evaluation2 statistical checks

> Stable prespecified calibration protocol, preserved before full calibration results.
> The model grid, seeds, counts and decision criteria below remain unchanged by the documentation refresh.

> Prespecified validation protocol for the matching-based method selected in Q141.
> Read with [the method specification](evaluation2-statistical-validation.md) and [retained behavior tests](../../src/test/network_defense/evaluation2/).
> Status: planned, not executed. The arithmetic probes in the method record are separate evidence.

## Purpose

The conditional mathematical proof establishes validity under the stated input model. These checks assess implementation, applicability, practical precision, and power. Passing a finite model grid is not a proof for every distribution.

Keep one small explicitly invoked validation runner. It must use the production numerical kernel without starting databases, Gust, or external simulation services. Keep it outside the default fast unit-test run. Do not build a second test framework.

Use independent, hand-derived quantities where available. Record the runner command, code/dependency identity, backend, numerical settings, seeds, dimensions, and dataset counts. Use validation seed `20261030`, with separate deterministic scenario/replicate streams and independent Pilot/Final data. Record the generator and its stream allocation. Do not choose or replace seeds after inspecting results.

## 1. Deterministic anchors

Behavior tests protect these before statistical simulation:

- Rectangular matching covers in both orientations; every cell appears once and each matching has distinct row/column coordinates.
- Hand-computed matching products and arithmetic averaging. Constant columns must not multiply evidence through the number of matchings.
- Past-only bets with a separate history per matching; known range is supplied by the frozen model.
- The five-row rare-event counterexample returns no false point certainty. A constant normalized contrast of -0.1 with five pairs gives p-value one under the selected recipe.
- Structural zero model range gives exact zero contrast, point interval, and p-value one.
- A constant normalized contrast of -0.1 with 160 pairs can reject in the first position of a 36-member Holm family whose other p-values are one. The recorded arithmetic probe gives raw p approximately 0.0008718. Derive an independent tolerance/oracle; do not copy implementation output into the expected value.
- Endpoint brackets, interval enlargement, empty-inversion fallback, and inclusive Decimal Holm decisions.
- Scaling all outcomes and model bounds by the same positive factor scales estimates/intervals while preserving p-values and decisions.

These are mathematical behavior cases, not a requirement to reproduce former Python outputs.

## 2. Controlled crossed-data models

Use bounded outcomes with known population means and range `H=1`. Include:

| Model | Required variation |
|---|---|
| Deterministic | Equal and unequal constant outcomes |
| Rare plan effects | Alternative row Bernoulli probability 0.1 and 0.01; constant reference equal to that probability under the null |
| Attack-only effects | Shared random column inputs, with no plan-selection variation |
| Shared-column cancellation | Both sides respond identically to attack inputs |
| Pure interaction | Mean-zero products of independent row and column signs |
| Mixed effects | Bounded row, column, and interaction terms; unequal side variability and useful/shared-column covariance |

Use independent Rademacher row signs `R_i` and column signs `V_j`. The fixed model equations are:

- Deterministic: `C=0.5`, `A=0.5+d`.
- Rare rows: `A=Z_i`, `C=p`, with independent `Z_i ~ Bernoulli(p)` and `p` in `{0.1,0.01}`. The true effect is zero.
- Attack-only: `A=0.5+d+0.2V_j`, `C=0.5`.
- Cancellation: `A=C=0.5+0.25V_j`.
- Interaction: `A=0.5+d+0.2R_iV_j`, `C=0.5`.
- Mixed: `A=0.5+d+0.1R_i+bV_j+0.1R_iV_j`, `C=0.5+0.2V_j`, with `b` in `{-0.1,0.1}`.

Use `d` in `{-0.1,0,0.1}` where present. Each equation stays within `[0,1]` and has true contrast `d` or the stated zero. Never clip a model afterward and claim its former mean. Shared row signs are permitted within the paired input; rows and columns remain independent.

Default count pairs are `(5,10)`, `(20,40)`, and `(100,200)`. Run 1,000 independent datasets per declared scenario/count cell for raw-test behavior. Assess interval coverage on the same cells; batching/cached preparations may reduce runtime. Profile before the full run. Any reduction must be declared before seeing results, justified, and reported as reduced evidence.

## 3. Error and coverage assessment

Use pointwise confidence 0.95 and family alpha 0.05. Check raw rejection at thresholds 0.05, 0.01, and the first threshold for the family being assessed.

For each check, count independent datasets that reject a true null or exclude the true effect. Report the rate and a binomial uncertainty interval. Nominal exclusion is at most the declared confidence error. Conservativeness is acceptable for validity; report its practical cost separately.

Before running, enumerate the total number `J` of error/coverage checks. Flag material excess with a one-sided binomial tail test under the nominal upper rate, using diagnostic threshold `0.01/J`. An exact tail calculation or a predeclared conservative binomial bound is acceptable. This controls false alarms across the diagnostic checks; it is separate from the study's Holm procedure.

A flag requires investigation. Do not widen acceptance bands, omit the scenario, or tune the method on the same results and call that a pass. Report any changed specification and run fresh prespecified checks. Absence of a flag is limited implementation evidence, not universal validity or proof that the error rate equals its nominal bound.

## 4. Family and Pilot selection

### Family behavior

Run 1,000 synthetic families at `(20,40)` and `(100,200)` for global-null and partial-null cases. Use six comparisons, shared reference `C=0.5+0.2V_j`, and alternatives from the mixed equation with row coefficient alternating between `+0.1` and `-0.1`. Share the row and column inputs across comparisons. Global-null effects are all zero; partial-null effects are `[-0.1,0.1,-0.1,0,0,0]`. Include the separate 36-member deterministic threshold anchor above.

Assess family error by counting whether any true-null member is rejected. Report power on false-null members separately. Apply the error-flag rule to family error as well. Raw-capital p-value checks can omit interval inversion for runtime if this is explicit: conservative interval fallback only raises the final p-value. Validate interval behavior separately and test the actual corrected result path in integration cases.

### Pilot planning

Run 100 complete statistical planning repetitions for a small shared-reference family. This is a numerical planning experiment, not a real application end-to-end study.

- Use candidates `(5,10)`, `(20,40)`, `(40,80)` in that order. Use unit plan and simulation cost coefficients, counting the shared reference once.
- Run a deterministic two-comparison family and a separate mixed two-comparison family. Each uses effects `[-0.1,0.1]` and its own shared reference. Use mixed column coefficient `+0.1`.
- Run both extra-capacity settings `(0,0)` and `(20,40)`.
- Use 32 outer samples, guard quantile 0.9, and target half interval span 0.2 in normalized units.
- Use the same confidence level for planning and Final.
- Run the actual outer-subset, guard-quantile, fan-in, and candidate-selection policy.
- Generate fresh independent Final data after selection.
- Report recommendation/insufficient frequencies, selected counts, per-comparison interval-size attainment, and joint family attainment with Monte Carlo uncertainty.
- Include an explicit insufficient override and report that it gives up the precision target.

The guard quantile is a planning heuristic. It is not a promised fresh-sample success probability. When a full-pool subset restores original logical order, all such subsets are identical; repeated evaluations add no fresh observations. Report predictive limitations rather than interpreting duplicated pool data as independent support.

## 5. Practical precision and performance

Report power and interval sizes on the known-effect models. No universal high-power requirement applies to arbitrarily small samples. A valid but weak result must remain visibly weak.

Profile a representative Final family and Pilot candidate workload. Record matrix dimensions, outer repetitions, runtime, and backend. Add CPU EXLA only for an observed need. Keep machine-speed thresholds out of unit tests.

Use these observations to recommend practical example counts. Do not turn a necessary minimum for possible rejection into a sufficient power or precision claim.

## 6. Completion evidence

The final report must distinguish:

1. Conditional mathematical validity and its assumptions.
2. Deterministic behavior-test results.
3. Synthetic error/coverage and family results with uncertainty.
4. Pilot planning performance and limitations.
5. Representative performance observations.
6. Actual local full-study evidence from the separate manual/backend end-to-end check.

No source implementation, empirical calibration result, or completed real study is claimed by this document.
