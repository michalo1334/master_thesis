# Native Evaluation2 calibration — 31 October 2026

## Assessment and scope

The complete prespecified synthetic protocol passed its declared diagnostic rule.
The run started at **22:40:21 UTC** and finished at **23:04:25 UTC** on 31 October 2026.
It used the production native kernel, fixed seed **20261030**, and the original model grid, counts and criteria.
No application, database, Gust engine or simulation service started during calibration.

This result supports implementation validity on the declared models under the stated assumptions.
It does not establish universal validity, a general power guarantee or a fresh-sample guarantee for the Pilot guard.
The separate [verification record](evaluation2-verification.md) owns real application-study evidence and retirement status.

## 1. Conditional mathematical validity

The estimand is the population mean mission-impact contrast, conditional on a frozen graph and model.
Independent IID row inputs contain plan-selection/scoring randomness.
Independent IID shared column inputs contain attack randomness.
The row and column collections are independent of each other.
Known finite outcome bounds come from the frozen model.

Each fixed matching contains distinct row and column inputs.
Its predictable bets use only that matching's past.
Arithmetic averaging preserves the separate capital expectations despite dependence between matchings.
The two-sided, sign-conservative p-value supports Holm correction under these assumptions.
Reported intervals remain pointwise.

Counts, matching order and tuning stay fixed before fresh Final data.
Pilot may select counts from independent information.
Timing replicas repeat scientific inputs and supply timing measurements; they add no outcome observations.
The [method-decision record](evaluation2-statistical-validation.md) contains the conditional argument and its scientific citations.

## 2. Deterministic behavior and review

The retained tests check matching covers in both rectangular orientations, hand-derived capital arithmetic, separate past-only histories, bounds, scaling, Holm and conservative interval policies.
Independent scalar arithmetic checks the native tensor results.
A threshold-side test checks both sides of each reported endpoint with a normalized step below the required tolerance.

The opt-in 1850-pair production comparison exposed an exact-floor defect in a log/exp round trip.
The owner shared the probability calculation between the fused and standalone paths.
The repeated check returns the literal smallest normal float64 value.
The final offline bundle passed **37 cases**, including that boundary.
Independent code/test/runner review returned **APPROVE**.

The 160-pair constant-contrast anchor produced raw p **0.0008717660682295909**.
The independent scalar result was **0.0008717660682295838**.
It rejects in the first position of a 36-member Holm family; the other members remain unrejected.
This anchor shows a possible rejection, rather than sufficient general power.

## 3. Synthetic error, coverage and family behavior

The [prespecified protocol](evaluation2-statistical-checks.md) defines the equations and assessment rule.
The executed grid contains deterministic, rare-row, attack-only, cancellation, interaction and mixed models.
All outcomes use the declared range `[0,1]` without clipping.

| Workload | Executed amount |
|---|---:|
| Scenario/count grid | 18 scenarios × three count pairs × 1,000 datasets = **54,000 datasets** |
| Count pairs | `(5,10)`, `(20,40)`, `(100,200)` |
| Six-comparison families | Global/partial null × two shapes × required mixed and additional declared deterministic models × 1,000 = **8,000 families** |
| Pilot planning | Two families × two extra capacities × 100 = **400 repetitions** |
| Error/coverage checks | 72 null-size + 54 coverage + eight family-error = **J=134** |

Confidence was 0.95 and family alpha was 0.05.
Raw-test thresholds were 0.05, 0.01 and 0.05/6.
Before outcomes existed, the runner declared a one-sided exact-binomial diagnostic threshold of **0.01/134**.
A check flags only when its observed rate exceeds the nominal upper rate and its tail falls below that threshold.
The run produced **zero flags**.

The largest null-rejection and interval-exclusion rates were both **2/1,000 = 0.002**.
Both occurred in the rare-row probability-0.1 model at `(100,200)` and threshold 0.05.
Their pointwise Wilson 95% interval was **[0.000549, 0.007263]**.
All remaining error/coverage checks recorded zero events.
For zero events in 1,000 independent datasets, the Wilson interval is **[0, 0.003827]**.

Every family-error cell recorded **0/1,000** families with a rejected true null.
Family error uses the permitted raw-capital path without interval inversion.
The conservative empty-inversion fallback can only raise the final p-value.
The grid separately checks the full interval path, and application integration checks the corrected result path.

Two stored binomial tails round to `1.0000000000002984`, which is approximately one.
Both checks are below their nominal rate, so that rounding changes no diagnostic decision.
The original machine evidence remains unchanged.

The uncertainty intervals are descriptive pointwise intervals, rather than simultaneous bands.
The diagnostic false-alarm rule is separate from the study's Holm procedure.
A finite grid and zero flags do not prove an error rate for every distribution.

### Power and precision cost

At `(100,200)`, deterministic normalized effects ±0.1 rejected at raw threshold 0.05 in all 1,000 datasets.
Their mean half-width was **0.070522**.
Their raw p-values still exceeded the first six-member Holm threshold, so those deterministic family cells had zero false-null rejection power.

For the mixed partial-null family at `(100,200)`:

| Event | Rate | Wilson 95% interval |
|---|---:|---|
| False-null member 0 rejected | 95/1,000 = 0.095 | [0.078345, 0.114754] |
| False-null member 1 rejected | 86/1,000 = 0.086 | [0.070169, 0.105000] |
| False-null member 2 rejected | 95/1,000 = 0.095 | [0.078345, 0.114754] |
| All three false-null members rejected | 41/1,000 = 0.041 | [0.030365, 0.055148] |

Each interval uses independent families as its denominator.
The runner does not treat dependent members as independent binomial trials.
The full machine report preserves every model's raw power and mean interval size, including weak results.

## 4. Pilot planning and fresh Final attainment

The experiment used candidates `(5,10)`, `(20,40)` and `(40,80)` in that order.
Each deterministic or mixed family had two comparisons with effects −0.1 and +0.1 and one shared reference.
Extra capacity was either `(0,0)` or `(20,40)`.
The actual native subset, guard-quantile, fan-in and candidate-selection policy ran with unit plan/simulation costs.
Three physical groups count the reference once.

The settings were 32 outer samples, guard quantile 0.9, target half-width 0.2 and shared confidence 0.95.
Every one of the four configurations recommended `(40,80)` in **100/100** repetitions.
Both individual comparisons and their joint family attained the target on fresh Final data in **100/100** repetitions per configuration.
Each corresponding Wilson 95% interval is **[0.963007,1]**.
Recommendation, insufficiency, selected-count and approval-stratified frequencies remain in the machine report.

At zero extra capacity, the largest candidate uses the complete pool.
Restoring logical order makes all its outer subsets identical.
Repeated evaluation of that pool adds no fresh observations or independent support.
The guard remains a finite-pool planning heuristic.

A separate explicit-insufficiency probe selected `(5,10)` after the actual selector returned insufficient.
Fresh-Final half-widths were about **0.700181**, above the unchanged 0.2 target.
The probe explicitly relinquished the target.
Application approval behavior is checked separately by integration tests and real insufficient-override studies.

### Practical count guidance

Use the small worked application example to check the execution protocol.
Its counts support wide uncertainty only.
For a normalized precision example, `(40,80)` attained half-width 0.2 in these planning models.
For confirmatory family decisions, the weak `(100,200)` family power warrants larger frozen candidates and workload profiling.
The 160-pair deterministic anchor is a necessary possibility check, rather than a general power recommendation.
Scale interval widths and targets by the actual frozen model range.

## 5. Performance and reproducibility

A fresh eager BinaryBackend comparison at `(100,200)` took **1.868268 seconds**.
That measured cost justified CPU EXLA 1.0.0.
The critical kernel uses the fixed `:host` client; Nx input preparation retains its recorded default backend.
Hot compiled comparisons took **0.027513–0.031789 seconds**; the first compiled call took **0.350799 seconds**.
No machine-speed threshold was added to tests.

The closing audit also measured a complete six-comparison Final numerical family at `(100,200)`, including every interval inversion and Holm correction.
It took **0.464870 s** on the first call and **0.191213 s / 0.160646 s** on repeated calls.
A two-comparison Pilot candidate used pool `(60,120)`, candidate `(40,80)`, 32 outer samples per comparison and guard 0.9.
It took **0.580210 s** first, then **0.509563 s / 0.475553 s**.
These CPU EXLA measurements repeat fixed inputs for performance only and add no calibration datasets.
The artifact is `local-results/evaluation2-native-performance-goal06.json`.

| Full-run section | Recorded elapsed time |
|---|---:|
| Grid | 544.620 s |
| Families | 584.266 s |
| Planning | 314.187 s |
| Whole run, including overhead | About 1,444.193 s |

The runner records Elixir/OTP, Nx/Decimal/EXLA versions, dependency-lock and source digests, backend/compiler, generator and stream allocation.
It checked **125,600 declared PRNG states** before generating outcomes and found no collision.
The master seed stayed unchanged.
Row, column, scenario, replicate and Pilot/Final roles use separate full-width roots.
Distinct deterministic streams implement the modeling assumption; they do not prove independence by themselves.

The full invocation used `scripts/evaluation2_calibration.exs --protocol --output` through `mix run --no-start` in the test environment.
The retained machine evidence is `local-results/evaluation2-calibration-goal06-20261031.json` and its incremental JSONL companion.
The report preserves every cell, count, rate, uncertainty interval, diagnostic and planning outcome.
Profile and aborted attempts remain separately labeled native evidence and contribute no datasets to this assessment.

## 6. Separate real application evidence

A fresh normal-application study used the retained RabbitMQ executor and real optimization/simulation effects.
It reached durable success after an explicit insufficient-Pilot override.
Its artifact is `local-results/evaluation2-native-study-goal06.json`.

The owner rechecked all three tiers, three warm-ups, 15 measured timing receipts, 108 unique optimization/experiment pairs, six 2×3 comparisons, scientific replica equality, snapshot identity and public/durable timing equality.
All estimates were zero, intervals were `[-8,8]`, p-values were one and no comparison rejected.
The five original development graph identities remained unchanged.
These observations establish the real small-count protocol; they do not establish useful study precision or power.

The first owner Final command stopped at a short tool bound.
The owner cancelled that incomplete execution and started a fresh execution.
No failed or interrupted measured replica was replaced.
The owned broker and its anonymous volume were removed after successful evidence collection.
