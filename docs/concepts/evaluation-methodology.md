# Evaluation methodology

This page defines the native Evaluation2 method for study authors and result readers.
The [study overview](evaluation-study-overview.md) describes the workflow.
The [operator guide](../evaluation2.md) describes input, commands and safe checks.

The primary outcome is simulated mission impact. Each declared alternative is compared with CVSS under the same action budget.
Inference is conditional on the frozen graphs and model settings.

## 1. Research scope and model

The research asks how defense strategies and controlled topology growth affect mission impact and runtime.
A study contains small, medium and large tiers. Each tier fixes one graph revision and one initial Host foothold.
Host count describes topology size; edge count and attack-relevant topology properties provide context.
One graph per tier supports conclusions about those scenarios. It does not sample a population of network topologies.

Mission impact is the sum of weights of disrupted mission capabilities.
The constructor freezes its model range as `[0, H]`, where `H` is the sum of finite positive capability weights.
Registered defense actions preserve those weights.
Bounds come from the model, rather than observed sample extrema.

At each step, the simulator selects an eligible attacker action uniformly, then samples its outcome.
The rules, iteration limit, maximum attempts and initial foothold define the shared attacker model.
CVSS values, success probabilities, support thresholds, required flows and capability weights are scenario inputs.
The initial foothold contributes to blast radius.

These are research-model outcomes. They do not estimate real exploit likelihood or operational loss without further model validation.

## 2. Treatments, reference and family

The definition chooses alternatives from the existing optimization strategies:

| Alternative | Selection basis |
|---|---|
| `random` | Random defense selection |
| `topology_segmentation` | Topology and reachability |
| `simulation_informed` | Simulation scoring |
| `simulated_annealing` | Stochastic search with simulation scoring |

CVSS is the implicit reference for every tier/budget context.
The primary comparison identity is `(tier, budget, alternative, cvss, mission_impact)`.
A budget limits the number of actions in a plan. It is an action-count limit, rather than an economic cost model.

One shared defense policy declares allowed action types and feasibility.
The application intersects allowed actions with each strategy's supported actions.
CVSS uses patches; topology segmentation uses segment-reachability blocks.
The constructor rejects a strategy whose effective action set is empty.

Scored strategies declare an objective and scoring trial count.
They inherit the shared simulation model and feasibility policy.
Scoring trials help select a plan; they are separate from outcome observations.

The family contains every declared alternative in every declared tier/budget context.
Comparison order is small, medium, large; then budget declaration order; then alternative declaration order.
For example, two alternatives and two budgets in each tier produce twelve comparisons.
A no-defense control or an alternative-versus-alternative contrast requires a separate, explicitly designed analysis.

## 3. Sampling units and aligned evidence

| Unit | Meaning | Purpose |
|---|---|---|
| Row input | One optimizer input, including its scoring randomness | Plan-selection variation |
| Column input | One attack seed, shared across rows and comparison sides | Attack variation |
| Timing replica | A fresh physical execution of fixed scientific inputs | Runtime variation |
| Frozen graph | One scenario in a size tier | Conditional interpretation |

For a comparison, let `A` contain alternative outcomes and `C` contain CVSS outcomes.
Both matrices have `n` rows and the same ordered `m` attack columns.
Row positions pair the two strategy outcomes under the declared selection input.
Columns preserve common attack seeds. A shared seed can still produce different paths after a defense changes the graph.

The statistical model assumes:

1. Row inputs are independent and identically distributed within their role.
2. Column inputs are independent and identically distributed within their role.
3. The row-input collection and column-input collection are independent.
4. Frozen model inputs deterministically map these inputs to outcomes.

Dependence within a row or column is expected.
All optimizer and stochastic scoring inputs belong to their row.
A reused stochastic scoring pool across rows, or scoring against Final attack inputs, would violate this model.
The retained optimizer derives scoring randomness from its selection input, separately from evaluation attack roots.

Physical collection uses unique strategy groups: one CVSS group and one group per alternative for each tier/budget.
Comparisons project those groups. A shared CVSS group can make comparisons dependent.
It owns one set of effects, rather than duplicate CollectionItems linked to the same effect.

```text
Alternative A rows ───────────→ A versus CVSS
CVSS rows ──────────────────┬─→ A versus CVSS
                           └─→ B versus CVSS
Alternative B rows ───────────→ B versus CVSS
```

## 4. Effect estimate and matching-based inference

The population estimand is the expected mission-impact difference over the declared row and column input distributions:

\[
\Delta = E\{A(R,T)-C(R,T)\},\qquad
\widehat\Delta=\overline A-\overline C.
\]

A negative estimate favors the alternative. A positive estimate favors CVSS.
The known contrast range is `[-H, H]`.

The frozen native method contract is `crossed-matching-betting-v1`.
Comparison results label its statistics `matching_bounded_mean_v1` and its marginal test `sign_conservative_betting`.
The family method label `holm` identifies the correction layer.
The numerical method partitions the difference matrix `D = A - C` into fixed cyclic matchings.
Each matching uses each participating row and column once.
Its observations are IID under the input model above.
Different matchings can remain dependent.

### Fixed matching cover

Use zero-based logical coordinates:

- If `n <= m`, matching `t` contains `(i, (i+t) mod m)` for all rows; there are `m` matchings.
- If `n > m`, matching `t` contains `((j+t) mod n, j)` for all columns; there are `n` matchings.

Each cell appears exactly once.
For a two-row, three-column matrix, the cover is:

| Matching | First pair | Second pair |
|---|---|---|
| 0 | `(0,0)` | `(1,1)` |
| 1 | `(0,1)` | `(1,2)` |
| 2 | `(0,2)` | `(1,0)` |

Logical order is fixed before observation.
Outcome values, selected-plan features, cost, seed magnitude and task completion order must not determine matching order.
The independent horizon in each matching is `min(n,m)`, rather than the total cell count.

### Predictable bets and pointwise intervals

For `H > 0`, normalize a difference to `X = (D/H + 1)/2` in `[0,1]`.
Within each matching, calculate positive and negative betting capitals.
Each bet uses only that matching's earlier observations.
The method fixes its variance initialization, confidence-dependent bet size and half-range cap.
These are versioned algorithm constants, rather than YAML controls.
The [method record](../history/evaluation2-statistical-validation.md#selected-capital-rule) specifies the exact recipe and its conditional mathematical argument.

Average capitals arithmetically across matchings, separately for each direction.
This preserves the null expectation bound despite dependence between matchings.
Invert the directional capitals at the two-sided threshold to obtain a closed interval.
The implementation retains conservative outer numerical brackets and enlarges the interval to include the all-cell estimate.

The interval is pointwise for one comparison at `analysis.confidence_level`.
Its half-width is half the full span; it need not be symmetric about the estimate.
The same confidence level applies to Pilot planning and Final reporting.
It is separate from `family.alpha`.

### Marginal p-value and boundary cases

To test zero population contrast, evaluate the directional capitals at normalized mean one half.
For a nonzero estimate, use the capital that agrees with its sign.
The raw p-value is `min(1, 2 / E_direction)`. A zero estimate receives one.
The factor two protects the two-sided test.
The direction choice only increases the valid two-sided bound.

The implementation uses float64 log arithmetic for capitals and conservatively handles positive underflow.
It uses no bootstrap draws or Monte Carlo tail counts for Final inference.

- If the model has `H = 0`, the contrast is structurally zero: estimate and interval are zero, and the p-value is one.
- Constant observed outcomes with `H > 0` retain sampling uncertainty.
- An empty interval inversion returns the full known contrast range, p-value one and an `empty_inversion` warning.
- Positive row and column counts are input eligibility conditions. They do not guarantee useful precision or power.

## 5. Complete-family Holm correction

Final analysis requires exactly one result for every frozen comparison.
It rejects missing, duplicate or foreign members before correction.

Holm orders raw p-values, multiplies each by the remaining hypothesis count, and applies a cumulative maximum capped at one.
The application uses Decimal arithmetic and restores the canonical comparison order.
The decision rule is inclusive: `adjusted_p <= family.alpha` rejects the zero-effect null.

Holm controls family-wise false rejection under valid marginal p-values.
It permits dependence from shared CVSS observations and other shared inputs.
It does not repair invalid marginal inference.
The reported intervals remain pointwise; Holm does not make them simultaneous or establish exact interval/test duality.

## 6. Precision Pilot

Pilot chooses one common `(plans, attacks)` candidate for fresh Final collection.
Candidate IDs, count pairs and order are frozen in the revision.
Pilot capacity is the coordinate-wise maximum candidate count plus `pilot.extra_pool`.
Extra capacity can be zero.

For each comparison and candidate:

1. Generate outcome-independent row and column permutations for each outer sample.
2. Take candidate-sized prefixes without replacement.
3. Apply the same row positions to both sides and the same attack columns throughout.
4. Restore logical order before matching-based inference.
5. Record the resulting interval half-width.
6. Take the linearly interpolated empirical guard quantile.

All candidates share permutation prefixes for a comparison and outer index.
An assessment passes when every outer result is informative and the guarded half-width is at most the target.
A candidate passes when every family comparison passes.

The guard quantile is a finite-pool planning heuristic.
It does not promise a fresh-Final success probability, either per comparison or jointly.
A full-pool subset contains the same observations in logical order each time.
Repeated outer evaluations then add no new evidence.

### Runtime selection heuristic

Among passing candidates, minimize:

\[
T(n,m)=L\,G\,n\{t_{plan}+m\,t_{attack}\},
\]

where `L` is the tier count, `G` is the largest physical group count in a tier, and costs are Pilot medians in milliseconds.
Count CVSS once per budget.
This is a ranking heuristic. It is not a prediction of full wall time with warm-up, replicas and orchestration overhead.

Ties prefer larger plan count, then smaller attack count, then earlier candidate position.
If none passes, the outcome is `insufficient`.
Both a recommendation and insufficiency lead to `awaiting_final`.

### Explicit approval and insufficient override

A recommendation requires explicit `:recommended` approval.
An insufficient Pilot permits `{:override_insufficient, candidate_id}` for one already-declared candidate.
The stored Pilot outcome stays insufficient beside the frozen selection.
Together, these values record the override; there is no separate override flag.

An override gives up the precision target.
It preserves the frozen family, method and fresh-Final inference assumptions.
The operator cannot use it to change the test after observing Final outcomes.
Failed or invalid Pilot work supplies no approval outcome.

## 7. Seeds, separation and fixed-sample limits

One master seed supplies the versioned `evaluation2-sha256-json-v1` derivation.
The root hashes a canonical JSON array of contract identity, seed and ordered role context, modulo `2^63 - 1`.
The constructor rejects collisions among distinct declared logical streams.

| Role | Scientific context |
|---|---|
| Selection row | Phase and zero-based row position; shared across strategies, budgets and tiers |
| Evaluation root | Phase and tier |
| Attack column | Evaluation root and the existing one-based simulation trial index |
| Pilot planning | Complete comparison identity, including budget |
| Pilot outer subset | Planning root, outer index and row/column role |
| Final inference | Deterministic matching and arithmetic; no resampling stream |

Pilot and Final use separate phase contexts and fresh physical effects.
Retries reuse an item's reserved effects.
Another phase, execution or timing replica uses fresh effects even when its scientific inputs agree.
Database UUIDs, scheduling, process identity and timing-replica positions do not determine scientific seeds.

Deterministic PRNG streams implement the IID-input model; distinct seeds alone do not prove independence.
Record seeds and contracts for replay, and state that modeling assumption when interpreting inference.

The validity argument is fixed-sample only.
Freeze counts, ordering, tuning and the family before fresh Final observations.
Do not stop early or increase scientific counts because interim Final outcomes look favorable.
Averaged capitals from different matching histories do not establish an anytime-valid process.

## 8. Warm-up, timing and equality

Final executes tiers in small/medium/large order.
Each tier performs excluded warm-up `-1`, then measured replicas `0..4` sequentially.
Every replica repeats scientific inputs with fresh optimization and simulation effects.
Timing replicas measure runtime variation; they do not multiply the inferential sample size.

The domain clock marks plan start, the shared plan-completion/simulation-start boundary, and replica end.
Thus total duration equals plan-selection plus simulation duration.
The intervals include scheduling, queue and retry delays inside these boundaries.
Preparation before plan start and later statistical analysis are outside these measurements.

The configured environment label must match the frozen label before each replica and at tier completion.
It is an operator assertion, rather than authenticated hardware/software identity.
Completed Gust receipts store durations in microseconds.
Raw monotonic readings stay in memory.
A lost incomplete clock session fails; timestamps and replacement replicas cannot supply missing measurements.

The equality gate compares all five measured scientific evidence sets.
It retains meaningful graph inputs, logical action targets, settings, seeds and outcomes.
It excludes generated effect/output IDs, timestamps, clock sessions and durations.
Only measured replica zero supplies representative Final evidence after equality passes.
Warm-up contributes neither inferential evidence nor timing summaries.

Report five measured values, median and observed range for each tier and metric.
For example, durations `31, 34, 35, 38, 42` seconds have median `35` and observed range `31–42` seconds.
This range describes those executions, rather than a population confidence interval.

## 9. Interpretation and verification limits

Read estimate direction, interval size, adjusted p-value and warning status together.
A non-rejection with a wide interval supports limited evidence, rather than equality of strategies.
An `informative` assessment means that numerical processing required no conservative fallback.
It does not certify power, precision or scientific calibration.

Blast radius, host compromises, capability disruption and pre-attack feasibility remain useful descriptive context in retained simulation records.
The current primary family analyzes mission impact only.
A secondary test requires its own declared estimand, method and multiplicity treatment.

The [verification record](../history/evaluation2-verification.md) preserves two real service-backed studies through durable success.
Both used an explicit insufficient override and two plans by three attacks per group.
Their six estimates were zero, intervals were `[-8,8]`, and raw/adjusted p-values were one.
These runs establish the native protocol at small counts. They do not establish useful precision, power or empirical calibration.

The [prespecified statistical checks](../history/evaluation2-statistical-checks.md) remain the calibration gate.
The [statistical validation record](../history/evaluation2-statistical-validation.md) preserves the rejected bootstrap counterexamples and method decision.
Keep those failures as history. The active method has no Python numerical fallback.

The derivation uses bounded-mean betting principles from [Waudby-Smith and Ramdas](https://doi.org/10.1093/jrsssb/qkad009)
and e-value averaging from [Vovk and Wang](https://doi.org/10.1214/20-AOS2020).
The cyclic crossed-matching adaptation and its full pipeline require their own stated assumptions and verification.
[Holm's procedure](https://www.jstor.org/stable/4615733) supplies the complete-family correction under valid marginal tests.
