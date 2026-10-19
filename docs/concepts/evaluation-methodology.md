# Preserved evaluation methodology

## Status and purpose

**The scientific methodology is preserved in this document.** Stage 1 removed the legacy evaluation subsystem during a clean rewrite. Git history holds the removed source code, schema definitions, transport formats, and executable setup. It does not hold old database rows.

This reference recovers the scientific baseline from Git commit `d94ba40352e469dc1c2da403ad3fa28397e5e350`. It separates the study protocol, the historical statistical method, and known historical inconsistencies.

The rewrite now has implemented, tested prototypes for one crossed comparison, a complete-family Holm correction, and a Precision Pilot. [The implemented evaluation pipeline](../inprogress/evaluation-pipeline.md) maps that software. The tests and deployed checks use synthetic evidence. They do not collect study data or produce study results. This document stays the scientific reference and is not an implementation plan.

A rewrite can change configuration or method, but it must identify that change explicitly. It must not silently change the estimand, sampling units, reference strategy, or correction family while claiming equivalent results.

## 1. Research scope and model

The reference study examined controlled topology growth and its relationship to:

- simulation runtime;
- defense-plan selection runtime;
- total evaluation runtime; and
- mission-impact differences between alternative defense strategies and CVSS prioritization.

The reference design used small, medium, and large tiers, with one frozen graph per tier. Host count controlled size. Edge count resulted from generation; it was not an independent treatment. A runtime pilot selected feasible sizes.

Across tiers, preserve the node roles, relationship types, exposure template, reachability-policy pattern, attacker entry context, and action-count budget interpretation. Record attack-relevant topology diagnostics. An unchanged diagnostic is a result, not an automatic failure.

Results are conditional on the frozen graphs. They do not estimate variation between independently generated graphs.

### Model assumptions

CVSS scores, exploit probabilities, capability-impact weights, minimum operational support, required flows, reachability policies, and defense-action semantics are controlled model inputs. Exploit probability is not an empirically measured real-world exploit rate.

The historical simulator selected an eligible attacker action uniformly, then sampled that action's outcome. The initial foothold contributed to blast radius. The attack horizon bounded action steps.

Mission impact is the model's weighted score for disrupted capabilities. Support thresholds and required flows determine operational status. Evaluation consumes that model-defined outcome; it must not silently redefine its weighting or scaling. The recovered study documents do not fully specify the simulator's aggregation formula.

## 2. Treatments, reference, and controls

The reference primary family compared these alternatives with CVSS prioritization:

| Alternative | Scientific role |
| --- | --- |
| Random defense selection | Randomized strategy benchmark |
| Topology-driven policy segmentation | Structural defense selection |
| Simulation-informed selection | Defense selection informed by simulated outcomes |
| Simulated-annealing search | Search over defense plans |

The **CVSS strategy is the primary comparison reference**. A **no-defense experiment is a separate descriptive control**. They are not interchangeable.

A primary comparison identifies a tier, budget, alternative, reference, and outcome. The historical primary outcome was mission impact. Direct alternative-versus-alternative claims were outside that primary family.

Action-count budgets control cardinality. Equal action counts do not imply equal monetary cost, deployment effort, operational risk, or implementation complexity.

## 3. Replication units and evidence alignment

| Unit | Meaning | What it estimates |
| --- | --- | --- |
| Plan-selection replicate | A plan selected for a strategy, budget, and selection seed | Selection variation |
| Attack replicate | A stochastic attacker execution against a plan | Attack/outcome variation |
| Timing replica | Repeated execution of fixed scientific inputs | Runtime variation only |
| Graph | One frozen topology in a size tier | A conditional scenario, not sampled graph variation |

Attack repeats cannot replace missing plan-selection replicates. Timing replicas do not add independent plans or attacks.

For each primary comparison, construct two matrices:

- alternative outcomes: plan rows × attack columns;
- CVSS outcomes: plan rows × the same attack columns.

All plans in a crossed comparison must share the same ordered attack columns. Reject unequal column coverage. The same attack seed identifies a shared column on both sides; defenses may still change the trajectory and outcome. Phase-level evaluation roots are a separate check, defined in Section 7.

**Pair attack columns, not plan rows.** Sample the alternative's plan rows independently of CVSS plan rows. Use stable plan and comparison identities for deterministic processing. Do not flatten all trials into independent observations.

Each tier must use compatible model variants and analysis settings. Verify the strategy/budget matrix, permitted selection seeds, required sample counts, and attack alignment before inference. Do not require all declared selection seeds when the protocol permits a selected subset.

## 4. Primary estimand and interval

Let $A$ contain alternative outcomes with $n_A$ plan rows and $m$ attack columns. Let $C$ contain CVSS outcomes with $n_C$ rows and the same $m$ columns.

The estimand is the difference between their mean mission impacts:

$$
\widehat{\Delta}=\overline{A}-\overline{C}.
$$

- Negative: the alternative produced lower simulated mission impact than CVSS.
- Positive: the alternative produced higher simulated mission impact.

The uncertainty target covers plan-selection and attack-outcome variation. It does not include graph-generation or deployment-environment variation.

### Corrected crossed bootstrap

For each bootstrap draw:

1. Sample $m$ attack-column indices with replacement.
2. Sample $n_A$ alternative plan-row indices with replacement.
3. Independently sample $n_C$ CVSS plan-row indices with replacement.
4. Apply the same sampled columns to both matrices.
5. Calculate the raw sampled mean contrast $\Delta_b$.
6. Apply the historical finite-sample correction:

$$
\gamma=\sqrt{
\max\!\left(\frac{n_A}{n_A-1},\frac{n_C}{n_C-1}\right)
\frac{m}{m-1}
},
\qquad
\Delta_b^*=\widehat{\Delta}+\gamma(\Delta_b-\widehat{\Delta}).
$$

For confidence level $1-\alpha$, use the $\alpha/2$ and $1-\alpha/2$ percentiles of the corrected draws. The interval half-width is half the difference between those limits.

The historically calibrated lower bounds were **five plan rows per side and ten shared attack columns**. These are method constraints in the reference implementation, not arbitrary transport limits. They are not a universal guarantee of interval coverage.

### Raw p-value: centered crossed bootstrap

The implemented primary test was **not a permutation test**.

Center each matrix by its own observed mean. Apply the same corrected crossed-bootstrap procedure to those centered matrices, using a separate deterministic random stream. For $B$ null draws:

$$
p_{\mathrm{raw}}=
\frac{1+\#\{b:|\Delta_{0,b}^*|\geq|\widehat{\Delta}|\}}{B+1}.
$$

The historical code used the configured bootstrap resample count for both the interval and this null distribution.

A comparison was non-informative when its estimated effect and both interval limits were numerically zero. The code set its raw p-value to one. A zero-width interval with a nonzero effect produced a degeneracy warning. Preserve these distinctions; do not interpret a zero-width result as proof of equivalence or certain precision.

## 5. Complete-family multiplicity correction

Declare the primary family before inspecting Final results. The historical example had four alternatives, three budgets, and three tiers: **36 primary comparisons**. That count is an example, not a universal constant.

Collect all expected primary rows, verify the complete key set, and apply **one Holm correction across the entire declared family**. Do not correct separately by tier, budget, or strategy. Do not silently omit inconvenient or non-informative rows to reduce family size.

Restore results to stable comparison identities after correction. The historical correction changed p-values only. Its displayed bootstrap intervals remained per-comparison intervals, not simultaneous familywise intervals.

No-defense, secondary outcomes, and exploratory comparisons do not enter this primary family unless the study explicitly declares a different family.

## 6. Precision Pilot

The precision Pilot selects common values for two dimensions:

- number of plan-selection replicates per comparison side, $n$;
- attacks per plan, $m$.

Declare a two-dimensional candidate grid, a target interval half-width, an upper guard quantile, an outer subsample count, and a Pilot random seed. Values are study configuration, not universal engine defaults.

Candidates must meet the calibrated lower bounds and fit every observed comparison on both sides. Reject an oversized candidate; do not truncate it silently.

### Candidate evaluation

For each candidate and required comparison:

1. Repeatedly select alternative rows, CVSS rows, and shared attack columns **without replacement** from Pilot evidence.
2. Run the corrected crossed bootstrap on each selected subsample.
3. Calculate its interval half-width.
4. Take the configured guard quantile of those half-widths.
5. Require the guarded value to meet the target and the evaluated evidence to be informative.

The outer subsampling is without replacement. The inner bootstrap is with replacement. These are different operations.

A candidate passes only if all required comparisons pass. Its reported guarded half-width is the maximum across comparison rows. Required non-informative comparisons block eligibility; a small numerical width alone is insufficient.

Candidate summaries are derived results. They are not observations from which to construct the crossed matrices.

### Runtime selection heuristic

Choose the passing candidate with the lowest predicted runtime. The historical heuristic was:

$$
T(n,m)=L\,G\,n\left(t_{\mathrm{select}}+m\,t_{\mathrm{trial}}\right),
$$

where:

- $L$ is tier count;
- $G$ is the maximum declared strategy-group count across tiers;
- $t_{\mathrm{select}}$ is median measured plan-selection duration;
- $t_{\mathrm{trial}}$ is median per-trial duration derived from experiment durations and trial counts.

The deterministic tie-break order is lower predicted runtime, then larger plan count, then smaller attack count. The heuristic does not establish a runtime confidence interval or a performance guarantee.

If no candidate passes, report an insufficient Pilot. Do not substitute a convenient failing candidate or proceed to Final claims.

## 7. Pilot/Final separation and scientific freeze

Each phase declares selection seeds and evaluation seeds. An **evaluation seed** is one tier's root for attack-related random streams. It is not a separate additional attack schedule. Pilot and Final use disjoint selection sets and disjoint evaluation-root sets.

The historical validation is asymmetric:

- Each tier declares one evaluation root. The set of observed roots across tiers must equal the phase's declared evaluation set.
- Each strategy run uses a non-empty subset of the phase's declared selection set. Every observed plan selection seed must belong to that set.
- Not every declared selection seed must appear in every tier or strategy. Final evidence may use a subset of its own declared selection set, sized according to the Pilot recommendation. It does not reuse Pilot seed values.

Do not reject a valid selection subset as incomplete. Do not accept missing declared evaluation roots.

The recommendation supplies Final configuration, not Final observations. Collect fresh Final evidence with the frozen common counts and fresh seeds.

The scientific sequence is:

```text
Freeze model/method → optimizer and topology/runtime pilots
    → precision Pilot → freeze common counts
    → freeze Final configuration, graphs, and environment
    → collect separate Final evidence → complete-family analysis
```

Optimizer/topology pilots choose feasible experimental settings. The precision Pilot selects outcome-sampling counts. They are not interchangeable.

A post-freeze change to scientific inputs creates a newly identifiable configuration or study revision. Do not patch measured evidence in place. This is a reproducibility rule, not a requirement to retain old executable deployments.

The Pilot-to-Final handoff remains an explicit approval/freeze boundary. Software orchestration must not silently turn Pilot evidence into Final data.

## 8. Warm-up and timing replicas

The reference runtime protocol used **one excluded warm-up and five accepted measured replicas per tier**.

The warm-up prepares the environment. It contributes neither timing evidence nor outcome evidence. Measured replicas repeat fixed scientific inputs and estimate runtime variation; they do not multiply the outcome sample size.

The historical report used median and observed range for simulation, plan-selection, and total-evaluation duration across accepted replicas. A changed environment record blocked measured collection.

Replica acceptance ignored expected run identifiers and timing values, but required matching scientific configuration, graphs, selected plans, attack and capability outcomes, pre-attack flow status, host compromises, and non-timing summaries.

Do not pool identical outcome replicas as independent plan or attack samples.

## 9. Secondary and descriptive results

Keep the scientific role of each result explicit:

- no-defense outcome context;
- blast radius, including the initial foothold;
- capability disruption and host compromise probabilities;
- pre-attack feasibility and required-flow disruption;
- variation between selected plans;
- empirical blast-radius distributions;
- plan-selection, simulation, and total runtime.

The historical secondary contrast used a simpler bootstrap over attack-level differences. It was not the crossed primary estimator. Do not substitute that calculation for primary inference or treat its outputs as corrected members of the primary family without a declared method change.

A feasibility-policy comparison must keep other model settings matched. Its scientific role must remain distinct from the declared primary strategy family.

## 10. Reproducibility and limits

Record enough information to reconstruct the scientific experiment: graph/model identity, attacker context, defense semantics, selected plans, outcome definition, strategy/budget family, phase schedules, sampling counts, confidence/resampling settings, random-stream policy, source/dependency versions, and measured environment.

Distinguish plan-selection seeds, evaluation roots, derived attack seeds, analysis seeds, and Pilot seeds.

Historically, comparison stream roots combined the relevant base seed with a tier offset and a comparison-index offset. Separate child streams served intervals and null draws. Pilot subsampling also used candidate counts and spawned child streams. Comparison identities were validated, but streams were not derived directly from those identities. Canonical ordering therefore matters for historical reproduction.

**Requirement on implemented software, not a claim about the removed legacy executor:** fixed scientific inputs, seeds, and ordering must produce equivalent results across retries and execution schedules. Worker count, completion order, and task IDs must not introduce new scientific randomness. Preserve the historical derivation or identify any replacement derivation explicitly; this document does not require a new identity-based seed scheme.

The exact historical offsets, stream derivation, and numerical-tolerance behavior remain recoverable from the baseline source. Bitwise reproduction also depends on random-generator and numerical-library versions.

Interpretation remains conditional on modeled exploit behavior, capability weights, frozen graphs, chosen budgets, and the measured environment. Equal budgets are not equal real-world cost. The topology design does not support population claims about arbitrary generated networks. Timing summaries do not establish performance on an unmeasured deployment.

The recovered documents do not fully establish universal optimizer settings or topology-construction defaults. Do not invent them as methodological constants.

## 11. Historical inconsistencies to keep explicit

1. **Permutation terminology:** Historical configuration/documentation included a permutation-resample parameter. The implemented primary p-value used the centered crossed bootstrap and bootstrap resample count. This document records that implementation; it does not silently choose a new permutation method. Any change needs an explicit statistical decision and validation. This statement concerns the primary test, not every secondary helper.
2. **Small illustrative example:** One old worked example used four plan-selection replicates, below the implemented/calibrated minimum of five. Do not treat that illustration as a valid primary-inference configuration.
3. **Model details:** Mission-impact aggregation/scaling and exact optimizer/topology defaults require the model definition or historical source where the study narrative is incomplete.

## 12. Historical sources

All paths below refer to **Git commit `d94ba40352e469dc1c2da403ad3fa28397e5e350`**, not current executable files. Recover them with Git; do not restore them into the working tree merely as references.

| Concern | Baseline source |
| --- | --- |
| Reference experiment, tiers, controls, timing protocol | `docs/inprogress/topology-scale-study.md` |
| Model assumptions, freeze rules, calibrated bounds, outcomes | `docs/inprogress/topology-scale-methodology.md` |
| Units, Pilot eligibility, phase separation | `docs/concepts/evaluation.md` |
| Historical configurable study example | `evaluation/studies/topology-scale.json` |
| Matrix alignment and primary statistics | `evaluation/analysis/src/network_defense_analysis/statistics.py`, especially the crossed-comparison builder and `_crossed_statistics` |
| Pilot subsampling, guard, recommendation, runtime heuristic | `evaluation/analysis/src/network_defense_analysis/study.py`, especially `_evaluate_candidate`, `_aggregate_candidate`, and `_candidate_order` |
| Full-family correction | The same historical `study.py`, `_apply_family_correction` |
| Descriptive and secondary analysis | `evaluation/analysis/src/network_defense_analysis/report.py` |

The methodology is the preserved reference. Archive members, CSV layouts, JSON field names, CLI commands, service routes, and deleted code structure are not preservation requirements.
