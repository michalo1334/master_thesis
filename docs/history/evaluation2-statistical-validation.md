# Evaluation2 statistical validation

> Stable method-decision record. It preserves the original failure diagnostics, alternatives and conditional mathematical audit.
> The [current methodology](../concepts/evaluation-methodology.md) defines supported usage. The [prespecified protocol](evaluation2-statistical-checks.md) defines the remaining calibration gate.

## Current gate

**Q141 selects matching-based bounded-mean betting. The native implementation and two real small-count full studies are verified. Full prespecified empirical calibration remains pending.**

The engineering workflow is largely specified. The previous numerical procedure is not an accepted statistical oracle. Independent review found material inference concerns, and direct diagnostics reproduce false certainty under a known population null.

The [current methodology](../concepts/evaluation-methodology.md) defines the implemented method and its assumptions.
The [stable verification record](../history/evaluation2-verification.md) preserves implementation evidence.
The failures and alternative-method assessments below remain as historical decision evidence. No full calibration pass is claimed.

## 1. Estimand and experimental units

The intended population contrast is:

\[
\Delta = E[Y_A(P_A,U)] - E[Y_C(P_C,U)],
\]

conditional on the frozen graph and model, with plan-selection and attack randomness treated as sampled inputs. A fixed recorded seed enables replay; conditioning literally on every realized seed would make the realized outcomes deterministic and change the uncertainty interpretation.

- Plan rows represent selection variation.
- Shared attack columns represent common attack-input variation.
- Timing replicas repeat these scientific units and add runtime measurements, not new outcome samples.
- One graph per tier supports graph-conditional conclusions.
- Shared CVSS observations create dependence between comparisons. Holm permits that dependence when marginal p-values meet its validity conditions.

The reviewer traced the current Elixir CVSS path and found deterministic ranking/tie handling, with no use of selection seed. Shared selection-seed values therefore do not alone prove a current paired-row error. If the reference or both sides become stochastic under common selection inputs, the method must account for that dependence or separate the streams. Verify the actual execution path before making stronger claims.

## 2. Executed counterexamples to the baseline

These examples validate a defect; they are not compatibility fixtures that the replacement must reproduce.

### Rare-event row variation

Let each alternative plan row be a Bernoulli(0.1) value repeated across all attack columns. Let the reference equal 0.1 in every cell. The population mean difference is zero.

With five independently sampled plan rows:

\[
P(\text{all alternative rows are zero}) = 0.9^5 = 0.59049.
\]

The observed dataset in that event was passed to the current Python calculation with 5-by-10 matrices, 999 bootstrap repetitions, 95% confidence, and seed 123.

| Output | Observed result |
|---|---:|
| Estimated contrast | approximately -0.1 |
| Interval | approximately [-0.1, -0.1] |
| Raw p-value | 0.001 |
| Informative | true |
| Zero-width warning | true |
| First Holm adjustment in a 36-member family | 0.036 |
| Rejection at alpha 0.05 | true |

If the remaining 35 p-values are one, Holm rejects this true-null comparison on the event above. This gives a false-rejection probability lower bound of 59.049% for that allowed row-dominated null model, rather than 5%. More bootstrap repetitions do not recover unobserved rare variation.

### Symmetric row variation

An earlier diagnostic used Bernoulli(0.5) alternative rows and a constant 0.5 reference, again with five rows and ten columns. The all-zero and all-one events have combined probability `1/16 = 0.0625` under the mean-zero population contrast.

Both observed datasets produced a point interval at -0.5 or +0.5 and raw p-value 0.0005 with 1999 repetitions. Even these two events alone exceed nominal 5% null rejection.

### Diagnostic execution

The checks ran the current `evaluation_compute.statistics.corrected_crossed_bootstrap` directly with NumPy matrices through the existing service virtual environment. `PYTHONDONTWRITEBYTECODE=1` prevented import-cache writes. The inline diagnostics used no project database or persistent probe file.

Compact reproduction shape:

```python
# Baseline diagnostic only; values describe the rare-event null sample.
A = np.zeros((5, 10))
C = np.full((5, 10), 0.1)
result = corrected_crossed_bootstrap(
    A, C, replicates=999, confidence_level=0.95, seed=123
)
```

The exact null probabilities above are analytical calculations. The function outputs were executed. Neither check is a completed Monte Carlo calibration study.

## 3. Other material review findings

### Finite-sample multiplier

The current multiplier is:

\[
\gamma=\sqrt{\max\{n_A/(n_A-1),n_C/(n_C-1)\}\,m/(m-1)}.
\]

The inspected code and sources supply no general coverage or testing-calibration derivation for it. Variance calculations in simple crossed models show different inflation factors for row-only, column-only, and interaction variation. It is not a universal variance correction.

The `(5,10)` limits are eligibility rules, not demonstrated coverage guarantees. Remove unsupported wording such as “calibrated minimums” until evidence supports a specified regime.

### Raw p-values and Holm

Centering a fitted bootstrap null and applying an add-one tail estimate does not automatically give super-uniform p-values. The add-one rule prevents zero reports; it does not independently validate the fitted-null test.

Holm does not repair invalid marginal p-values. Review raw-test size separately from interval coverage, including partial-null families and shared-reference dependence.

### Pilot precision

A guard quantile over subsets of the observed Pilot pool is a planning heuristic until fresh-Final precision attainment is validated. If a candidate uses the entire pool, outer subsets contain the same observations, apart from order; width variation then comes from inner Monte Carlo randomness.

Fresh Final evidence prevents Pilot-based selection from directly reusing the inferential sample. Preserve that separation and freeze the family/procedure before Final. An insufficient-Pilot override gives up the precision target; it does not justify a different Final test after seeing Final outcomes.

## 4. Source evidence

The literature scout identified these primary sources:

- Owen and Eckles (2012), *Bootstrapping data arrays of arbitrary order*: https://doi.org/10.1214/12-AOAS547 . Supports factor-wise resampling under stated crossed-array assumptions; does not establish this implementation's multiplier, percentile interval, fitted-null test, or eligibility guarantees.
- McCullagh (2000), *Resampling and Exchangeable Arrays*: https://doi.org/10.2307/3318577 . Establishes the importance of array exchangeability/dependence rather than observation-level resampling.
- Holm (1979), *A simple sequentially rejective multiple test procedure*: https://www.jstor.org/stable/4615733 . Family-error control depends on valid marginal p-values and permits dependence among tests.
- McDiarmid (1989), *On the method of bounded differences*: https://doi.org/10.1017/CBO9781107359949.008 . Gives exponential concentration for functions of independent inputs with bounded coordinate changes.

These sources support principles, not automatic acceptance of the current implementation.

## 5. Method decision and alternatives

Q141 selects C. A and B remain recorded alternatives that explain the choice; they are not runtime engine options.

### A. Revised, explicitly approximate crossed-bootstrap inference

Use a justified resampling model, conservative treatment of unresolved empirical degeneracy, and a supported count/distribution regime established by theory and calibration. Remove unsupported finite-sample guarantees. Validate both marginal null rejection and family behavior, not only interval width.

A warning alone is not an adequate remedy for the executed counterexample. A small arithmetic correction or a larger bootstrap count is not a validity argument.

### B. Conservative inference using known outcome bounds

**Independent mathematical audit: valid under the stated independent-input model. No final method selection yet.**

Let each outcome lie in a known model range `[L,U]`, with `H = U-L`. Let independent row inputs and independent shared column inputs generate the crossed observations. The two input collections must also be independent. Identical distributions within each role connect the expectation to the intended population estimand.

For paired row inputs, replacing one input changes the mean contrast by at most `2H/n`. Replacing one shared column input changes it by at most `2H/m`. Therefore:

\[
Q=4H^2(1/n+1/m),\qquad
r_\alpha=\sqrt{\tfrac{Q}{2}\log(2/\alpha)}.
\]

McDiarmid gives a confidence interval `[estimate-r, estimate+r]`. Intersecting it with the known contrast range `[-H,H]` preserves coverage.

For the inspected deterministic-in-selection CVSS reference, replacing a row changes only the alternative. Its coordinate bound is `H/n`, giving the tighter:

\[
Q=H^2(1/n+4/m).
\]

Under the population null `Delta=0`, define:

\[
p=\min\{1,2\exp(-2\widehat\Delta^2/Q)\}.
\]

For any `0<t<1`, the event `p<=t` implies an absolute deviation at least `sqrt((Q/2) log(2/t))`. McDiarmid bounds that event's probability by `t`. Thus this p-value is super-uniform under the assumptions, and Holm supports strong family-error control despite dependence between comparisons. If `H=0`, the known contrast is zero and `p=1`.

The actual mission-impact calculation sums positive frozen capability weights for disrupted capabilities. The normal graph changeset enforces positive weights, so `[0,sum(weights)]` is valid when weights are finite. Registered actions remove edges and preserve those weights. Establish finite bounds once at construction. If a supported path permits signed weights, use the sum of negative weights and sum of positive weights as bounds instead.

Outcome units are not automatically normalized. The current seed generator declares capability weights 3 and 5. Bounds for a frozen graph containing those capabilities use `H=8`. Derive the actual range from the graph; do not infer it from the observed data.

#### Analytical cost illustration

The table uses the tighter CVSS bound, `H=1`, and pointwise 95% intervals. Multiply radii by the actual range `H`.

| Plan rows | Attack columns | Cells per group | Guaranteed radius / H |
|---:|---:|---:|---:|
| 5 | 10 | 50 | 1.052 |
| 20 | 40 | 800 | 0.526 |
| 100 | 200 | 20,000 | 0.235 |
| 369 | 1,476 | 544,644 | at most 0.100 |

At `(5,10)`, the smallest possible raw p-value is about 0.07135, so this bound cannot reject at 0.05. Final warm-up plus five measured replicas multiplies physical outcome collection by six. These are calculations for this conservative bound, not an empirical calibration or a universal sampling lower bound.

The radius depends on counts and the model range. The Pilot guard quantile cannot certify a narrower guaranteed interval. Choosing this route therefore changes Pilot precision planning as well as Final inference.

Distinct/hash-derived seeds do not prove statistical independence. State the independent-input model explicitly; deterministic PRNG streams implement the simulation's modeling assumption. A recorded seed supports replay without changing that interpretation.

The implementation may differ radically from the old calculation if the resulting method is sound and its precision/cost trade-off fits the study.

### C. Matching-based bounded-mean betting — conditional mathematical pass

Q141 adopts this method. The independent audit found no material mathematical flaw under the fixed-sample IID-input assumptions below. This is our crossed-data adaptation of bounded-mean betting, rather than a published validation of this complete pipeline. Practical power and implementation correctness remain acceptance work.

#### Observation model

Keep the same crossed contrast matrix `D[i,j] = alternative[i,j] - reference[i,j]`, with known `D` range `[-H,H]`. Partition its cells into fixed matchings. Each matching uses distinct row inputs and distinct column inputs, so its observations are IID under the declared product-input model.

Use the frozen logical row and trial indices. Do not order by observed outcomes, plan/scoring features, seed values, cost, timing, or completion order. Such ordering can destroy the required sampling argument even when Final outcomes were not inspected. Absorb all optimizer/scoring randomness for a plan into its row input; do not reuse a stochastic scoring pool across rows or score against Final attack inputs.

For `n<=m`, matching `t` uses pairs `(i,(i+t) mod m)` for every row. There are `m` matchings. For `n>m`, use `( (j+t) mod n,j)` for every column and `n` matchings. Every cell appears once; matchings are dependent on each other.

#### Selected capital rule

Normalize each difference to `X=(D/H+1)/2` in `[0,1]`; its target mean is `mu=(Delta/H+1)/2`.

Within each matching, calculate positive and negative betting capitals. Each next bet uses only earlier observations in that matching. It must not use the current observation, another matching's data, or the whole-matrix variance.

The selected recipe uses a past-only variance proxy and a fixed half-range cap. Within a matching, observations are indexed from one; initialize the running mean at one half and variance proxy at one quarter. Each squared prediction error uses the running mean before that observation:

- Past mean: `(0.5 + sum(previous X)) / (previous count + 1)`.
- Past variance proxy: `(0.25 + sum(previous squared prediction errors)) / (previous count + 1)`.
- Base bet: `sqrt(2 log(2/confidence_error) / (matching_size * past_variance))`.
- Positive cap: `0.5/mu`; negative cap: `0.5/(1-mu)`.
- Positive factor: `1 + positive_bet * (X-mu)`.
- Negative factor: `1 - negative_bet * (X-mu)`.

Handle zero denominators as an unbounded cap, while the base bet remains finite. These are fixed method constants, not operator settings. With confidence error `delta`, the exact updates are:

\[
\widehat\mu_t=\frac{1/2+\sum_{i=1}^t X_i}{t+1},\qquad
\widehat v_t=\frac{1/4+\sum_{i=1}^t(X_i-\widehat\mu_{i-1})^2}{t+1},\qquad
b_l=\sqrt{\frac{2\log(2/\delta)}{k\widehat v_{l-1}}}.
\]

Use one shared interval confidence level for Pilot planning and Final reporting. Keep family alpha separate. Matching coordinates are zero-based array positions; simulation trial seed indices remain one-based.

The audit establishes that each matching capital has null expectation one. Its factors stay at least one half and use only the matching's own past. Arithmetic averaging across matchings preserves that expectation despite their dependence. Keep positive and negative averages separate as `E_plus` and `E_minus`.

The two-sided p-value is `min(1, 2/max(E_plus,E_minus))` at normalized mean one half. The maximum is not itself a mean-one e-value; the factor two is required by the union bound. The sign-selected version uses `min(1,2/E_plus)` for a positive all-cell contrast, `min(1,2/E_minus)` for a negative contrast, and one for zero. This only raises the valid two-sided p-value. Holm then permits dependence among comparisons.

The positive capital decreases with the candidate mean; the negative capital increases. Invert each at threshold `2/confidence_error` to obtain the lower and upper endpoints. Union Markov bounds exclusion of the true mean by the confidence error. Handle structural `H=0` equality before normalization.

Preserve the all-cell mean as the point estimate. Enlarging an interval to include it preserves coverage. An empty inversion can return the full known range and p-value one conservatively. Report these as pointwise intervals. Neither Holm adjustment nor interval enlargement supplies simultaneous coverage or exact p-value/interval duality. Use closed confidence intervals and the approved inclusive `adjusted_p <= alpha` decision. Exact boundary differences do not establish a bug or an unclaimed duality.

This proof is fixed-sample only. Freeze counts, matching construction/order, and tuning before fresh Final evidence; independent Pilot information may select the counts. Do not stop or increase the scientific sample because interim Final evidence looks favorable. Averaged capitals from different matching filtrations are not automatically an anytime-valid process.

#### Executed arithmetic diagnostic

A disposable inline Python calculation implemented the proposed past-only capital arithmetic for column-constant data. In this special case all fixed matchings have identical streams, so their average equals that one capital. No repository implementation or database operation was involved.

For known range `H=1`, observed differences constantly `-0.1`, and 95% confidence:

| Independent pairs per matching | Raw directional two-sided p-value | Unenlarged interval |
|---:|---:|---:|
| 5 | 1.0000 | approximately [-0.737, 0.663] |
| 20 | 0.7538 | approximately [-0.362, 0.218] |
| 100 | 0.01577 | approximately [-0.164, -0.023] |
| 160 | 0.0008718 | approximately [-0.141, -0.051] |

Exact enumeration of all 32 five-row Bernoulli(0.1) patterns in the rare-event null example gave rejection probability zero at 0.05 for this diagnostic rule. It avoids the reproduced point-certainty failure in that example. This is neither general calibration nor proof of useful power across crossed-data models.

Use float64 and log-sum-exp for arithmetic capital averages. Form the bounded log p-value before exponentiation and conservatively floor positive underflow to the smallest normal float64 value. For confidence inversion, retain outer brackets until normalized width is at most `1e-10`, with at most 64 bisections. Return the outer lower/upper brackets rather than their midpoint. These are numerical policies, not an interval/test duality claim.

The mathematical audit checked the matching cover, IID-pair argument, predictable bets, averaging, two-sided p-value, monotonic inversion, interval enlargement, and source-level scoring/attack roles. Its outcome is a conditional pass. It does not establish a universal power advantage: the matching horizon is `min(n,m)`, and the method can discard useful information when one input dimension has no actual variation.

The implemented method cites bounded-mean betting principles from Waudby-Smith and Ramdas (doi:10.1093/jrsssb/qkad009) and e-value aggregation from Vovk and Wang (doi:10.1214/20-AOS2020).
These principles support the conditional argument; their papers do not independently validate this crossed-matching adaptation.

## 6. Acceptance work

Before handing off the full source implementation:

1. Record the selected matching-based method and its independently reviewed assumptions (Q141: done).
2. State what is confirmatory, approximate, unresolved, or merely a planning heuristic.
3. Set the supported count/data regime without presenting eligibility checks as statistical guarantees.
4. Update numerical types, schema/settings, and behavior cases to match the selected method.
5. Define reproducible calibration criteria before inspecting calibration results.
6. Independently review the mathematical specification.

The [prespecified statistical checks](evaluation2-statistical-checks.md) define controlled models, dimensions, error flags, family checks, planning evaluation, and reporting. They are planned, not executed.

During implementation validation, run those checks and the real full study. If the supported regime fails, correct or restrict the method and report the evidence rather than declare completion.
