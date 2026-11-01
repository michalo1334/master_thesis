# Evaluation2 methodology, explained

For an Elixir programmer with basic statistics. Read sections 1–10 in order. The later sections provide evidence, implementation references and optional detail.

**All tables marked “synthetic” contain invented teaching data. They are not study findings or recommended sample sizes.**

The [method specification](evaluation-methodology.md) defines the current contract. The [operator guide](../evaluation2.md#thesis-scientific-check) defines its explicit checks. This guide explains why the method has those parts.

## 1. Start with the research question and one observation

The research asks how defense-selection strategies and controlled topology growth affect simulated mission impact and runtime. It predicts no winning strategy.

For one fixed network and action cap, the primary question is:

> Over repeated plan-selection and attack inputs, how much mission impact would this strategy produce compared with CVSS?

One **outcome observation** is one mission-impact score after one attack trial against one selected defense plan. A comparison cell contains two aligned outcomes: alternative and CVSS. Their difference measures the alternative's change in impact for those inputs.

Lower impact is better. We always subtract in this order:

`difference = alternative impact − CVSS impact`

A negative difference favors the alternative. It describes that observation before it supports any claim about an average over new inputs.

Runtime answers a separate question about execution cost. Repeating the same scientific inputs for timing does not produce new independent outcome observations.

## 2. First generate plans; then compare strategies

A **strategy** is a policy for choosing defense actions. A **plan** is its selected list of actions. CVSS, the Common Vulnerability Scoring System, supplies the reference priority order for patching. A CVSS score is not an exploit probability.

| Strategy | How it selects actions |
|---|---|
| CVSS reference | Prioritizes vulnerability patches by CVSS |
| Random | Chooses uniformly among currently eligible action/target candidates |
| Topology segmentation | Uses topology and reachability |
| Simulation-informed | Scores choices with simulated attacks |
| Simulated annealing | Searches plans using simulation scores |

The shared policy declares allowed action types. Each strategy uses its supported subset. Different action sets remain part of the treatments being compared.

The approved **action budget** is a maximum cap: one, two or three actions for every strategy. A cap of three permits a shorter plan when no eligible action remains. Report the requested cap, actual use and targets, including empty plans. Equal caps compare selection policies; they do not force equal realized plan lengths. These model counts do not measure money, deployment effort or operational risk.

Random selection refreshes a reproducible uniform permutation at each step. The optimizer takes the first affordable, feasible, useful candidate. Thus an infeasible candidate does not hide a feasible alternative later in the permutation. Each feasible, useful candidate has the same chance of being first. The plan seed and remaining positive budget determine the step's draw; chance can repeat an ordering.

“Useful” means that the action still changes the graph. For example, revoking credentials again after all outgoing authentication links disappear adds no useful action. Duplicate action types receive no extra weight. Under **required feasibility**, actions must preserve the modeled mission's pre-attack feasibility. Under **unrestricted feasibility**, usefulness still applies, but a plan can disrupt mission operations before an attack.

Simulation-based scores help choose the plan. The later evaluation attacks measure that chosen plan. Their random-input roles stay separate.

```text
selection inputs → strategy and any scoring trials → selected plan
selected plan + evaluation attack inputs          → outcome matrix
aligned outcome matrices                         → statistical comparison
```

The statistical comparison never chooses a defense. Matching and evidence updates only read collected scores. They create no new observations.

### What mission impact measures

Mission impact is the sum of weights of disrupted mission capabilities. A capability can fail through lost support, a missing required flow, or modeled compromise of a required service.

The frozen model supplies the range `[0, H]`. Here `H` is the sum of finite positive capability weights. Defense actions preserve those weights. The range therefore comes from the model, before outcomes exist.

For our synthetic example, use eight unit-weight capabilities. Then impact lies in `[0, 8]`, and an alternative-minus-CVSS difference lies in `[-8, 8]`. Observing only small scores would not reduce that known range.

## 3. One synthetic matrix, from outcomes to mean difference

Fix one synthetic network, one cap and one alternative. Use three plan-selection inputs, called rows R0–R2. Use four evaluation attack inputs, called columns T0–T3. Each column is shared across plans and both strategies.

Each row position pairs the alternative and CVSS under the declared selection input. CVSS currently selects deterministically, so its plan can repeat across rows.

These hand-chosen values illustrate arithmetic. For the uncertainty interpretation, imagine outcomes collected under the input assumptions in section 4. The toy itself has no sampled-input provenance and demonstrates no coverage rate.

**Synthetic outcomes** — every entry is a mission-impact score:

| Row | Alternative T0 | T1 | T2 | T3 | CVSS T0 | T1 | T2 | T3 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| R0 | 1 | 2 | 6 | 1 | 5 | 4 | 6 | 3 |
| R1 | 3 | 4 | 8 | 3 | 5 | 4 | 6 | 3 |
| R2 | 2 | 3 | 7 | 2 | 5 | 4 | 6 | 3 |

Subtract CVSS cell by cell:

| Synthetic difference D | T0 | T1 | T2 | T3 | Row mean |
|---|---:|---:|---:|---:|---:|
| R0 | −4 | −2 | 0 | −2 | −2 |
| R1 | −2 | 0 | 2 | 0 | 0 |
| R2 | −3 | −1 | 1 | −1 | −1 |

The alternative mean is `42 / 12 = 3.5`. The CVSS mean is `54 / 12 = 4.5`. The **observed mean difference** is therefore `−1` mission-impact point.

This is an observed improvement on these inputs. The **target mean**, written Δ, concerns new plan and attack inputs from the declared input distributions, with this network and model fixed. The observed mean, written Δ̂, estimates it:

\[
\Delta = E[A(R,T)-C(R,T)],\qquad
\widehat\Delta = \frac{1}{nm}\sum_{i,j}D_{ij}=-1.
\]

Think of Δ as the average of a conceptual repeatable workload. Δ̂ is the average of this one collected workload. We need uncertainty because another set of inputs can give another Δ̂.

## 4. Why twelve cells are not twelve independent observations

Cells in a row share a selected plan and its selection/scoring input. Cells in a column share an attack input. These common causes can make scores move together. This structure is called **crossed data**: each row input meets each column input.

Sharing attack inputs is useful. Both strategies face aligned attack randomness instead of unrelated lucky or unlucky draws. Their difference can cancel common attack variation. A shared seed can still lead to different attack paths after defense changes the graph; cancellation is useful when present, not guaranteed.

The inference assumes:

1. Row inputs are independent and identically distributed within their role.
2. Column inputs are independent and identically distributed within their role.
3. The row collection and column collection are independent of each other.
4. The frozen model maps these inputs deterministically to outcomes.

“Identically distributed” means the same input-generating rule applies within that role. All stochastic plan scoring belongs inside its row input. A shared scoring pool across rows, or scoring against Final attack inputs, breaks this observation model.

A **seed** is a reproducible address for pseudorandom input. It is not a unit of independent evidence by itself. Separate phase/role streams implement the model's independence assumption; distinct seed integers do not prove it.

An Elixir process controls execution. It does not create statistical independence. Sending the same row to another process, copying a matrix, or repeating an attack with the same scientific input repeats the input. These operations can test replay or measure runtime; they cannot increase the outcome sample size.

More attack columns explore the existing plans more thoroughly. They cannot reveal a rare type of plan that none of the sampled rows selected. In the implemented method, each independent sequence below has length `min(plans, attacks)`. Adding attacks beyond the plan count leaves that length unchanged. Extra attacks can still change the evidence average, but they do not remove the need for enough plan inputs.

## 5. Fixed matchings: use the crossed data without pretending it is independent

Choose cells that share neither a row nor a column. Under the input assumptions, those cells use disjoint independent inputs. One such sequence is a **matching**.

For our synthetic 3×4 matrix, the fixed cyclic cover is:

| Matching | Logical cells, in order | Difference sequence | Mean |
|---|---|---|---:|
| M0 | (R0,T0), (R1,T1), (R2,T2) | −4, 0, 1 | −1 |
| M1 | (R0,T1), (R1,T2), (R2,T3) | −2, 2, −1 | −1/3 |
| M2 | (R0,T2), (R1,T3), (R2,T0) | 0, 0, −3 | −1 |
| M3 | (R0,T3), (R1,T0), (R2,T1) | −2, −2, −1 | −5/3 |

Every cell appears once. Each matching contains three IID observations under the stated model. Here **IID** abbreviates independent and identically distributed.

The average of these four matching means is still `−1`. The point estimate uses all cells. The matching construction protects the uncertainty calculation.

Different matchings share row and column inputs, so they remain dependent. We must combine their evidence in a way that permits that dependence.

The cover and order use fixed logical positions. Sorting by outcomes, plan quality, seed magnitude or task completion would change the sampling argument. The matching is a statistical arrangement of existing observations, not another execution of a plan.

## 6. Evidence updates: a fair test of a proposed average

Suppose someone proposes an average difference, such as zero. The method asks how much evidence the observed sequences supply against that proposed mean.

Imagine a checking game that starts with capital one. Before each observation, the rule sets a stake using only that matching's earlier observations. The next score changes the capital. A rule that chooses the stake before seeing the next score is **predictable**.

At the proposed true mean, each update has conditional expected factor one. Final capital therefore has expectation one under that mean. It stays nonnegative. Such a quantity is an **e-value**: large values provide evidence against the proposed mean through an expectation bound. It is neither an effect size nor a probability that a hypothesis is true.

Each matching runs two games: one for differences above the proposed mean, and one for differences below it. Every game has its own past. The rule cannot borrow the current observation, another matching's history or whole-matrix variance to set a stake.

Normalize the scores before the update. Our range is H=8, so `X = (D/8 + 1)/2`. Zero difference becomes `X=0.5`.

For M0, the synthetic differences `−4, 0, 1` become `0.25, 0.5, 0.5625`. At proposed zero difference, the implemented cap makes each stake one in this small example. The below-zero game has factors:

```text
1 − (0.25   − 0.5) = 1.25
1 − (0.5    − 0.5) = 1
1 − (0.5625 − 0.5) = 0.9375
capital = 1.25 × 1 × 0.9375 = 1.171875
```

The third score partly opposes the proposed improvement, so the capital decreases at that step. The fixed general stake recipe appears in [optional detail](#15-optional-mathematical-detail).

### Average evidence; do not multiply dependent games

The synthetic directional capitals at zero difference are:

| Matching | Above-zero capital | Below-zero capital |
|---|---:|---:|
| M0 | 0.796875 | 1.171875 |
| M1 | 0.9228515625 | 1.0458984375 |
| M2 | 0.8125 | 1.1875 |
| M3 | 0.7177734375 | 1.3447265625 |
| Arithmetic average | **0.8125** | **1.1875** |

Averages preserve the expectation bound even when the matchings depend on each other. Multiplying these dependent capitals would need a different justification.

This calculation uses every cell once within the cover. Four dependent matchings do not become four new independent experiments.

## 7. From evidence to a p-value and an interval

The **null comparison** is Δ=0: equal population mean mission impact for this strategy/CVSS context. Equal means would still permit different plans, variability or individual attack outcomes.

Because the synthetic estimate is negative, the implementation uses the below-zero capital. Its two-sided raw p-value is:

\[
p=\min(1,\ 2/1.1875)=1.
\]

The factor two protects the two possible directions. Selecting the direction from the estimate is conservative relative to using the larger directional capital with the same factor.

A valid **p-value** has this calibration property: under the zero-mean null and the stated assumptions, `P(p ≤ q) ≤ q`. Thus a rule that rejects at 0.05 has false-rejection probability at most 0.05 for this one comparison. A reported p-value is not the probability that the null is true. Our `p=1` supplies no rejection; it does not establish equality.

### An interval asks about many proposed means

Instead of testing only zero, test proposed averages across the known range. The **confidence interval** retains the averages that the directional evidence does not exclude. At 95% confidence, each directional threshold is `2 / 0.05 = 40`.

The implementation retains conservative outer numerical brackets. It also enlarges the interval to include the all-cell estimate. If inversion fails to produce an ordered interval, it reports the full known range, p-value one and an `empty_inversion` warning.

For this synthetic matrix at 95% confidence, the production kernel returns:

| Synthetic output | Value |
|---|---:|
| Observed mean difference | −1 |
| Pointwise interval | [−8, 8] |
| Half-width | 8 |
| Raw p-value | 1 |
| Numerical warnings | None |

Why does the interval keep even the range endpoints? Recalculate the games at each proposed endpoint, with the same past-only recipe:

| Proposed average difference | Normalized proposed mean | Relevant averaged capital | Exceeds 40? |
|---|---:|---:|---|
| −8 | 0 | Above-mean: about 21.4865 | No |
| +8 | 1 | Below-mean: about 35.5586 | No |

Neither endpoint crosses the exclusion threshold, so the interval remains the full model contrast range. Use the averaged capitals here; one matching's larger capital cannot replace the prescribed average.

The interval leaves possible average benefit and harm unresolved. Its half-width eight exceeds the one-point target. Even though no numerical fallback occurs (`informative=true`), this example is too imprecise for admission. The word “informative” is a numerical status, not a useful-precision guarantee.

**Confidence level** describes repeated-design coverage. If we repeat the fixed design under its assumptions, at least 95% of the intervals cover the fixed target Δ. It does not assign a 95% posterior probability to Δ inside this particular interval.

**Precision** means interval tightness. Its half-width is `(upper − lower)/2`; the interval can be asymmetric around Δ̂. The approved target is one mission-impact point in original units, independently of the p-value. A wide interval can be valid and practically unhelpful. Non-rejection with a wide interval is not equivalence.

## 8. Why the complete family has 36 comparisons

The study asks the same primary question in every declared context:

`3 tiers × 3 maximum caps × 4 alternatives against CVSS = 36 contrasts`

The tiers are small, medium and large. The caps are 1/2/3. The alternatives are the four strategies in section 2. Every contrast concerns mission impact. No-defense and alternative-versus-alternative comparisons are outside this family.

If we inspect many tests, one can reject a true null by chance. The **family** is the complete frozen set for which we control that risk. **Holm correction** protects the chance of at least one false rejection across it, even when comparisons share CVSS outcomes.

Holm sorts raw p-values. It multiplies the smallest by 36, the next by 35, and so on. It then applies a cumulative maximum, caps values at one and restores comparison order. The rule rejects when `adjusted p ≤ family alpha`. Here **alpha** is the chosen family false-rejection limit, separate from interval confidence.

Carry our synthetic result into a complete synthetic family: suppose the other 35 raw p-values also equal one. All 36 adjusted p-values equal one. Nothing rejects. The observed improvement of one point remains an observation, rather than an established average benefit.

For scale only, consider a separate hypothetical p-value of 0.001 with 35 others equal to one. Its adjusted value would be `36 × 0.001 = 0.036`, which rejects at family alpha 0.05. This hypothetical value does not come from our matrix. The first Holm threshold is about `0.05/36 = 0.001389`.

Final requires exactly the frozen family: missing, duplicate and foreign results fail validation. Choosing only favorable contrasts afterward would change the error claim. Holm depends on valid raw p-values; it cannot repair a faulty marginal test.

The intervals remain **pointwise**: each interval covers its own target at its stated level. Holm does not turn 36 pointwise intervals into a simultaneous confidence statement. Nor does it make interval exclusion of zero exactly equivalent to a Holm decision.

## 9. Pilot, fresh Final and the three scientific checks

We need enough rows and columns for useful precision, but collection costs time. **Pilot** is a separate planning dataset. **Final** is fresh outcome evidence at the accepted fixed counts.

Pilot assesses a declared list of `(plans, attacks)` candidates. It takes outcome-independent row/column subsets, applies the same positions to both sides, restores logical order and checks interval half-widths. A guard quantile summarizes those widths: for example, the 0.9 quantile is a high value in that observed width distribution. A comparison passes when every subset result is numerically informative and its guarded half-width is at most the target. Every comparison must pass for a candidate to pass.

Among passing candidates, the selector uses Pilot timing medians to rank estimated collection cost. CVSS counts once per cap. Ties prefer more plans, fewer attacks and then earlier candidate order. This ranking is a heuristic, not a full wall-time prediction.

The **guard quantile** is also a planning heuristic. It describes subsets of one observed pool; it does not promise a fresh-Final success probability. Repeating a full-pool subset in restored order repeats the same evidence.

A recommendation needs explicit acceptance. If Pilot is insufficient, an explicit override can select an already-declared candidate. The insufficient outcome remains visible. The override gives up the precision target; it changes neither the method nor the family.

The approved thesis design adds explicit `ScientificCheck` calls:

| Boundary | What the author/operator must establish |
|---|---|
| Preflight, before Pilot | Three resolved tiers, caps 1/2/3, four alternatives against CVSS, 36 contrasts, finite positive model ranges and one-unit half-width target |
| Freeze, after Pilot choice and before fresh Final | Retain the definition and declared candidate counts; preserve settings, family, seed schedule, source identities and freeze chronology |
| Result, after Final | Match the frozen values and complete canonical native result; check the numerical contract and every actual interval half-width |

`preflight/1`, `freeze/2` and `check_result/3` are manual application boundaries. The study commands do not call them automatically. `freeze/2` returns a value-bound integrity record; it neither stores it nor proves when it was created. The caller retains that record and chronology.

Keep three conclusions separate:

1. **Native Final success:** the software workflow completed.
2. **Numerical contract validity:** identities, bounds, method labels, statistics structure and Holm outputs satisfy the contract. This check is not a proof of modeling assumptions or a recomputation of raw evidence.
3. **Achieved precision:** all 36 actual half-widths are positive and at most one original mission-impact point.

A wide interval gives `insufficient_precision`. A collapsed interval gives `investigate`. A zero-range model also stops this thesis study for investigation, although generic arithmetic correctly handles a structurally zero contrast.

The test is **fixed-sample**. Before fresh Final, freeze counts, logical order, tuning and family. The predictable updates inside a matching do not authorize peeking until significance. Averaging different matching histories does not establish an anytime-valid process. A wide Final retains its original sample and finding. A new design needs separate authorization, a new freeze and fresh observations; adaptive extension is outside this method.

### Timing replicas and collection cost

Final uses one excluded warm-up and five measured timing replicas per tier. Each replica repeats scientific inputs with fresh physical effects. The five measured scientific evidence sets must agree; then replica zero supplies representative outcomes. Replicas add timing measurements, not plan rows or attack columns.

With all approved strategies, there are 15 physical groups per tier and 45 overall: three caps times CVSS plus four alternatives. For n rows and m columns, warm-up plus five replicas require `270n` optimization/experiment pairs and `270nm` evaluation attack trials. Strategy-internal scoring adds work. Inferential matrices still have n×m cells per group.

Report the five measured durations, median and observed range. That observed timing range is a summary of those executions, not a population confidence interval. Boundaries include queue/scheduling/retry delay between plan start, plan completion/simulation start and replica end. They exclude earlier preparation and later statistical analysis.

## 10. A separate descriptive feasibility question

A defense can block attacks by also breaking the mission. We therefore describe pre-attack feasibility separately from the primary outcome comparisons.

Start required and unrestricted policy members from the same initially feasible graph revision. Match strategy, maximum cap and selection seed. Keep the declared scoring trials for scored strategies. Compare:

- ordered actions and actual action use;
- missing required service flows;
- weighted mission disruption before any evaluation attack.

Keep empty and short plans. Both members retain usefulness eligibility. This matched procedure describes how the policy changes selected defenses. It adds no p-values or contrasts to the 36-member primary family.

The [current method](evaluation-methodology.md#9-scientific-study-admission) specifies the retained procedure. The [Goal 07.1 summary](../inprogress/evaluation2-goals/progress/07.1-scientific-corrections.md) records a 45-pair controlled fixture validation and replay. Its detailed temporary exports were deleted at the author's request. Treat that number as a summarized historical validation, not available raw thesis observations or a new effectiveness finding.

## 11. Why this inference method, and what the alternatives can offer

The task needs an average contrast with crossed input dependence, known finite bounds and a complete family. Rare plan effects make small empirical samples risky. The selected method makes its bounded-input argument explicit while retaining uncertainty for constant observed data.

The following choices have different evidence status. “Not benchmarked” means the retained work supplies no comparable performance result.

| Actual method candidate | Basis and potential value | Retained status, cost and limits |
|---|---|---|
| Previous crossed-bootstrap implementation | Resampled rows/columns of the empirical data | Retired after executed false-certainty counterexamples. Its multiplier and fitted-null test lacked a general validity argument. No current runtime fallback. |
| Revised crossed bootstrap | Could use justified factor-wise resampling under crossed-array assumptions | Considered, not implemented or benchmarked as a replacement. Needs a supported sample/distribution regime and raw/family calibration. It can be useful; the previous failure does not condemn bootstrap methods generally. |
| Conservative bounded differences | Bounds how much replacing one independent input can change the mean | Conditional mathematical argument and analytical cost examples only. Count-driven intervals can be wide. No production alternative or empirical benchmark. |
| Fixed matching bounded-mean betting | Uses IID observations within fixed matchings, known bounds, predictable updates and arithmetic evidence averages | Selected and implemented. Has independent arithmetic tests and retained synthetic calibration. The horizon is min(n,m); conservative family power and physical collection cost remain limits. No universal efficiency claim. |

### Tempting shortcuts and model-dependent possibilities

| Approach | What would justify it | Status here |
|---|---|---|
| Treat every matrix cell as an independent replicate | Independence at the cell level | The actual shared-input design does not supply this assumption. More cells alone cannot justify its standard error. |
| Ordinary t-test on all cells | Its assumed sampling/error structure | Not an audited replacement for these crossed data. A t-based analysis of suitably independent summaries can be appropriate under its own assumptions. |
| Crossed random-effects or mixed model | A defensible row/column/interaction model and a valid small-sample inference procedure | A model-dependent possibility, not an implemented, calibrated or benchmarked candidate in this decision. Could gain efficiency if its assumptions fit. No measured ranking is available. |
| More bootstrap draws, processes or copies | New independent input information, when that is what is missing | More numerical repetitions improve numerical stability in suitable algorithms; they do not recover an unobserved kind of plan. |

### Why the rejected implementation matters

A retained historical counterexample used rows that equal one with probability 0.1 and zero otherwise, repeated across all attack columns. CVSS always equaled 0.1. The population difference was zero.

With five rows, all alternative rows are zero with probability `0.9^5 = 0.59049`. The old implementation reported a point interval near −0.1 and raw p=0.001 for that dataset. In a 36-member family with the other p-values one, Holm gave 0.036. Thus the recorded implementation could reject a true null on an event with probability at least 59.049%.

This is an analytical probability paired with a recorded executed diagnostic, not a new experiment. The [stable method-decision record](../history/evaluation2-statistical-validation.md#2-executed-counterexamples-to-the-baseline) preserves it. The retired implementation and removed audit archives were not restored or rerun for this guide.

Owen and Eckles' [crossed-array bootstrap work](https://doi.org/10.1214/12-AOAS547) supports factor-wise resampling under stated assumptions. It does not validate the rejected multiplier or fitted-null test. [Bounded differences](https://doi.org/10.1017/CBO9781107359949.008) supplies another conservative route. [Bounded-mean betting](https://doi.org/10.1093/jrsssb/qkad009) and [e-value averaging](https://doi.org/10.1214/20-AOS2020) support the selected component principles. This project's crossed-matching adaptation still needs its own assumptions and verification.

## 12. What the retained evidence establishes

**Calibration** checks a method on synthetic data whose generating process and true target are known. It can reveal implementation errors and practical weakness. A finite grid cannot prove performance for every distribution.

The [prespecified protocol](../history/evaluation2-statistical-checks.md) and [retained report](../history/evaluation2-calibration-20261031.md) cover:

- 54,000 datasets across deterministic, rare-row, attack-only, cancellation, interaction and mixed models;
- 8,000 six-comparison families, plus a separate 36-member deterministic threshold anchor;
- 400 planning repetitions with fresh Final data;
- 134 declared error/coverage checks, with zero flags under the prespecified excess-and-tail rule.

These are existing calibration results, not runs conducted for this explanation. The raw file is `local-results/evaluation2-calibration-goal06-20261031.json`. It retains stale scaffold/no-pass wording alongside full-count protocol data. The report identifies that discrepancy. Its assessment applies the prespecified rule to the recorded counts and rates; a status string alone supplies no acceptance evidence.

Conservativeness has a cost. In the retained mixed partial-null six-member family at `(100,200)`, all three nonzero-effect members rejected in only 41/1,000 independent families. The report gives uncertainty and per-member results. That observation warns about power; it neither predicts 36-member thesis power nor benchmarks competing methods.

**Power** is the chance of detecting a real nonzero target in a specified design/model. **Precision** is interval size. A valid method can have low power and wide intervals. The deterministic 160-pair rejection anchor establishes possible rejection, not adequate counts for every model.

Retained small local application runs validate workflow execution and replica equality. They have wide intervals and supply no strategy-superiority or equivalence finding. The later full-36 local diagnostic's exact output survives only in the concise Goal 07.1 record; its removed exports are unavailable.

The updated [thesis methodology](../../../thesis/chapter_methodology.tex) keeps a further boundary: substantive strategy, topology-scale and cloud-runtime conclusions require accepted evidence from the declared Azure study environment. A local pipeline phase named “Final” is not that acceptance decision.

Inference is conditional on frozen graphs, attacker rules, success probabilities, mission weights and input distributions. One graph per size tier does not sample a population of networks. Correct uncertainty arithmetic does not validate the model's realism, real exploit probabilities or operational loss. Those require separate evidence.

## 13. How this maps to Elixir

Use these few source boundaries when terminology becomes abstract:

| Concept | Actual module/type boundary |
|---|---|
| Frozen study and accepted counts | `Study.Definition`, `Study.Selection` under `NetworkDefense.Evaluation2` |
| Outcome matrices to estimate, interval and raw p | [`Study.Compute`](../../src/lib/network_defense/evaluation2/study/compute.ex), with `Compute.Input` and `Compute.Matching` |
| Past-only updates and dependent evidence averages | [`Compute.Betting`](../../src/lib/network_defense/evaluation2/study/compute/betting.ex) and its numerical kernel |
| Complete-family result and admission | `Study.Result`; [`Study.ScientificCheck`](../../src/lib/network_defense/evaluation2/study/scientific_check.ex) |

Illustrative Elixir-shaped pseudocode, not an API recipe:

```elixir
fixed_design = retain_design_and_accepted_counts(planning_data)
fresh_scores = collect_at_fixed_inputs(fixed_design)

comparisons =
  for context <- fixed_design.family do
    differences = aligned_difference(fresh_scores, context)
    evidence = evaluate_fixed_matchings(differences, fixed_design)
    summarize_mean_interval_and_raw_p(evidence)
  end

correct_complete_family(comparisons)
report_contract_and_precision_separately()
```

The [operator guide](../evaluation2.md#elixir-api) supplies the supported API. The statistical argument concerns sampling and evidence, not the programming language. Elixir organizes the pipeline, Nx/CPU EXLA executes float64 numerical work, and Decimal handles Holm arithmetic. These choices do not create independence or prove a statistical method valid.

## 14. Common mistakes

| Mistake | Correct reading |
|---|---|
| “Cap three means exactly three actions.” | Three is the common maximum; retain and report early stops. |
| “Random can choose a useless revocation under unrestricted policy.” | Unrestricted relaxes feasibility; useful-action eligibility remains. |
| “The alternative averaged one point lower, so it is better on average.” | The toy shows an observed improvement; its uncertainty does not establish a population benefit. |
| “A new process or timing replica adds an independent sample.” | Independence concerns new scientific inputs under the input model. |
| “Matching discards the other cells.” | The cover uses every cell once, with separate histories and dependent evidence averages. |
| “Betting updates optimize the defense.” | They evaluate proposed means after plan generation and scoring. |
| “p=0.03 means a 3% chance that the null is true.” | A p-value calibrates a rejection rule under the null assumptions. |
| “A 95% interval gives this target a 95% posterior probability.” | Confidence is repeated-design coverage. |
| “No rejection means equivalent strategies.” | A wide interval can leave important benefits and harms unresolved. |
| “Holm makes every interval jointly 95%.” | Holm corrects family test decisions; reported intervals stay pointwise. |
| “ScientificCheck or succeeded proves the study is precise.” | Read actual widths, assumptions and the separate admission finding. |
| “Keep adding Final rows until the result is useful.” | This method fixes counts before fresh Final; a new design needs fresh observations. |

## 15. Optional mathematical detail

### Why arithmetic averages remain valid evidence

For a proposed true normalized mean μ, each matching capital has expectation at most one. If there are M dependent matchings, linearity gives:

\[
E\left[\frac{1}{M}\sum_t E_t^\pm(\mu)\right]\leq1.
\]

No independence between matchings is needed for this equality/inequality. Markov's inequality bounds the chance that one directional average reaches `2/δ` by `δ/2`. Combining the two directions bounds interval exclusion by δ. The maximum of the two capitals is not itself a mean-one e-value; the two-sided factor remains necessary.

### The predictable stake recipe

Let δ be one minus the fixed confidence level. Within each matching, k is its fixed length. At step ℓ, use only its earlier normalized observations:

\[
a_{\ell-1}=\frac{1/2+\sum_{q<\ell}X_q}{\ell},\quad
v_{\ell-1}=\frac{1/4+\sum_{q<\ell}(X_q-a_{q-1})^2}{\ell},\quad
b_\ell=\sqrt{\frac{2\log(2/\delta)}{k v_{\ell-1}}}.
\]

The positive stake is `min(bℓ, 0.5/μ)`. The negative stake is `min(bℓ, 0.5/(1−μ))`. A zero denominator leaves the finite base stake uncapped in that direction. Factors are `1 + stake⁺(X−μ)` and `1 − stake⁻(X−μ)`. They stay at least one half.

For our toy, k=3 and δ=0.05. The initial base stake is about 3.1364. At μ=0.5, both caps equal one. All later base stakes also exceed one, which justifies the unit-stake arithmetic in section 6. At other proposed means, the stakes and capitals change; interval inversion is not a fixed-stake extrapolation.

### The conservative alternative's analytical radius

For both paired strategy outcomes potentially changing with a row input, bounded differences gives:

\[
Q=4H^2(1/n+1/m),\qquad r_\delta=\sqrt{(Q/2)\log(2/\delta)}.
\]

Intersect `[Δ̂−rδ, Δ̂+rδ]` with `[-H,H]`. For CVSS deterministic in selection, the tighter coordinate bound gives `Q=H²(1/n+4/m)`.

At n=5, m=10 and 95% confidence, the tighter radius is about `1.052H`. This is an analytical illustration for that conservative route, not a measured benchmark or a universal lower bound on valid interval width.

## 16. Contextual glossary

| Term | Meaning in this study |
|---|---|
| Row / plan input | One draw of selection inputs, including stochastic scoring; reused over attack columns |
| Column / attack input | One evaluation attack draw shared across rows and strategies |
| Seed | Reproducible input identifier; independence still needs the observation model |
| Timing replica | Physical rerun of fixed scientific inputs for runtime measurement |
| Target mean / estimand | Expected alternative-minus-CVSS impact over the declared input populations, with graph/model fixed |
| Estimate | All-cell observed mean difference used to estimate that target |
| Uncertainty / precision | Sampling uncertainty about the target / tightness of its interval |
| Null | Proposed target difference zero |
| Matching | Ordered cells with distinct rows and columns |
| Predictable update | Stake chosen from that matching's past before its next observation |
| E-value / capital | Nonnegative evidence quantity with null expectation at most one |
| Raw p-value | Single-comparison calibrated measure used in the family correction |
| Confidence / pointwise | Repeated-design coverage / coverage for one target at a time |
| Family / Holm | Frozen set of 36 questions / correction controlling any false rejection across them |
| Pilot / Final | Separate count planning / fresh fixed-count inference |
| Calibration | Checks on synthetic generators with known target values |

## 17. Optional self-checks, with worked answers

These questions are reading aids. The author does not need to pass a quiz.

1. **What does −1 establish in the synthetic matrix?** The observed mean is one point lower: 3.5 versus 4.5. The target mean over new inputs remains uncertain.
2. **Why does M0 have three independent observations?** Its three cells use three distinct row inputs and three distinct column inputs. The IID product-input assumptions supply independence and the common distribution.
3. **Can we multiply M0 and M1's capitals as independent evidence?** They reuse input rows/columns. The implemented justified combination is their arithmetic average with the other matching capitals.
4. **Why is the toy p-value one?** The selected below-zero capital is 1.1875. `min(1, 2/1.1875)=1`. This leaves the zero-mean null unrejected without assigning it a probability.
5. **What if we copy the four columns ten times?** We gain no new attack draws. The copy does not meet the independent-column assumption for a new 40-column scientific sample.
6. **Can a valid native Final fail scientific admission?** Yes. A contract-consistent interval of `[-8,8]` has half-width eight, above the one-point target. A collapsed interval requires investigation instead.
7. **Does a 95% interval plus Holm give a 95% probability that all 36 targets lie inside their intervals?** No. The intervals are pointwise. Holm supplies family false-rejection control for valid marginal tests.
8. **What should happen after a wide Final?** Preserve its counts and result. Report insufficient precision. A future design needs a separate freeze and fresh data, rather than extending this Final adaptively.

## 18. Short recap

Generate plans under equal maximum caps. Evaluate them with aligned attack inputs. Estimate alternative-minus-CVSS mission impact from all cells. Respect shared-input dependence through fixed matchings, past-only evidence updates and arithmetic evidence averaging. Report pointwise intervals and complete-family Holm decisions separately. Use Pilot for planning and fresh fixed-count Final for inference. Check actual precision independently of software success. Keep model validity and accepted Azure evidence as separate requirements.

A paced walkthrough can start with the matrix and the meaning of −1. The next step is why shared rows/columns change uncertainty. Understanding the guide can only be checked through the author's feedback.
