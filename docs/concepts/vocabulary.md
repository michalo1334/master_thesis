# Vocabulary

Use one term for one meaning throughout the model, simulation and native Evaluation2 guides.
The [methodology](evaluation-methodology.md) defines statistical assumptions and formulas.
The [operator guide](../evaluation2.md) defines the supported input and commands.

## Graph

- **Graph:** A network context model of typed nodes and directed relationships.
- **Graph revision:** One immutable version of a graph.
- **Optimized graph revision:** A graph revision with the changes selected by an optimization run.
- **Tier:** One fixed size slot: small, medium or large. A study freezes one graph/Host input per slot.

## Simulation

- **Simulation:** A Monte Carlo experiment on one graph revision.
- **Experiment:** The saved simulation record and its trials.
- **Trial:** One attacker trajectory.
- **Iteration:** One attacker action step in a trial.
- **Simulation seed:** The root from which the existing simulation policy derives one seed per one-based trial index.
- **Baseline simulation:** A descriptive simulation on the source graph before defense actions.
- **Blast radius:** The final number of foothold hosts, including the initial foothold.
- **Mission impact:** The sum of weights of disrupted mission capabilities.
- **Modeled pre-attack mission disruption:** Required-flow or mission-support loss caused by defenses before attacker footholds are applied.

## Optimization

- **Defense action:** One selected graph change that reduces modeled attack impact.
- **Strategy:** A method for selecting defenses under a budget.
- **Plan:** The actions selected for one strategy, budget and row input.
- **Budget:** The maximum action count an optimization run can apply.
- **Null strategy:** A no-defense control in the optimization domain; it is outside the native study's primary alternative list.
- **Pre-attack feasibility:** The condition that every mission capability is operational before an attack.
- **Scoring trial:** An optimization-internal simulation used to choose a plan, separate from study outcome observations.

## Evaluation and study

- **Evaluation2:** The native study subsystem under `NetworkDefense.Evaluation2.Study`.
- **Comparison:** An alternative-versus-CVSS mission-impact analysis for one tier and budget.
- **Reference strategy:** CVSS prioritization, implicit in each native comparison.
- **CVSS prioritization:** Vulnerability-patch selection based on CVSS severity.
- **Family:** The frozen ordered set of all declared primary comparisons.
- **Complete family:** Every expected comparison exactly once, with no foreign member.
- **Identity:** `(tier, budget, alternative, reference, outcome)`, which names one comparison.
- **Estimand:** The population mean alternative-minus-CVSS mission-impact contrast under the declared input model.
- **Estimate:** The all-cell alternative mean minus the all-cell CVSS mean. A negative value favors the alternative.
- **Canonical order:** Small/medium/large, then declared budgets, then declared alternatives. Object key and completion order are irrelevant.
- **Physical group:** One tier/budget/strategy collection. A CVSS group supplies several logical comparisons.
- **Model bound:** The frozen mission-impact range `[0,H]`, derived from finite positive capability weights.

## Evidence and sampling

- **Evidence matrix:** One strategy's outcomes, with logical plan rows and common attack columns.
- **Row input:** The optimizer input and all its scoring randomness for one plan position.
- **Plan-selection replicate:** One plan row for a strategy, budget and selection input.
- **Attack column:** One attack seed shared across plan rows and comparison sides.
- **Column alignment:** Identical ordered attack seeds in both matrices and all rows.
- **IID-input model:** Independent identically distributed inputs within each role, with row and column collections independent of each other.
- **Matching:** A fixed set of matrix cells with distinct row and column inputs. Its observations are IID under that model.
- **Matching cover:** The cyclic partition that includes every contrast cell exactly once.
- **Outer subsample:** An outcome-independent Pilot subset without replacement, restored to logical order before inference.
- **Timing replica:** A fresh physical execution of fixed scientific inputs, used to measure runtime variation rather than add inferential observations.

## Seeds and randomness

- **Master seed:** The single operator input for all versioned scientific seed derivation.
- **Seed contract:** `evaluation2-sha256-json-v1`, the canonical ordered-role hashing rule.
- **Plan-selection seed:** A phase/row-derived seed shared across strategies, budgets and tiers.
- **Evaluation root:** A phase/tier-derived root shared across that tier's groups.
- **Attack seed:** The existing simulation child seed for one one-based trial index.
- **Planning seed:** A Pilot root for one complete comparison identity, including budget.
- **Outer seed:** A planning-derived row or column permutation seed for one outer index.
- **Phase seed separation:** Distinct Pilot and Final scientific contexts, checked for logical stream collisions.

Final inference is deterministic; it needs no resampling seed.
Distinct deterministic seeds support replay, while statistical independence remains a modeling assumption.

## Statistics

- **Matching-based bounded-mean betting:** The native fixed-sample method using predictable bets within each matching and arithmetic capital averages across matchings.
- **Predictable bet:** A bet based only on earlier observations in the same matching.
- **Capital:** A product of bounded betting factors under a candidate mean.
- **Interval:** A closed pointwise confidence interval from directional capital inversion, conservatively enlarged to contain the all-cell estimate.
- **Half-width:** Half the interval span, `(upper - lower) / 2`; it need not equal the distance from the estimate to an endpoint.
- **Raw p-value:** The valid marginal zero-contrast test bound before family correction, under the declared assumptions.
- **Adjusted p-value:** The complete-family Holm-adjusted value.
- **Holm correction:** Decimal step-down adjustment with canonical output order and inclusive `adjusted_p <= alpha` rejection.
- **Pointwise coverage:** Coverage for one comparison. The reported intervals have this scope.
- **Family-wise error:** Probability of at least one false rejection in the family, controlled by Holm under valid marginal tests.
- **Informative assessment:** Numerical processing needed no conservative fallback; this does not certify precision or power.
- **Empty inversion:** A numerical inversion with no accepted interval; the method returns the full known contrast range, p-value one and a warning.
- **Structural zero range:** A graph model with `H = 0`; its contrast is known zero before observing outcomes.
- **Fixed-sample inference:** Counts, order, tuning and family freeze before fresh Final evidence. Interim outcome-based stopping is outside the supported argument.

See [native inference](evaluation-methodology.md#4-effect-estimate-and-matching-based-inference).
The rejected bootstrap and its failed diagnostics remain in the [method decision history](../history/evaluation2-statistical-validation.md).

## Precision Pilot

- **Precision Pilot:** Collection and analysis used to select common Final plan/attack counts.
- **Candidate:** One declared ID and positive `(plans, attacks)` pair.
- **Pilot capacity:** Coordinate-wise maximum candidate counts plus non-negative extra pool capacity.
- **Candidate comparison:** One candidate's assessment for one family comparison.
- **Outer subsample count:** Number of observed-pool subsets assessed for each candidate/comparison.
- **Guard quantile:** The interpolated empirical quantile of outer interval half-widths; a planning heuristic rather than a fresh-Final success probability.
- **Guarded half-width:** The half-width at that guard quantile.
- **Worst guarded half-width:** The largest guarded value across a candidate's comparisons.
- **Recommendation:** The candidate that passes every comparison and ranks first under the runtime heuristic and tie-breaks.
- **Insufficient Pilot:** A valid outcome with no passing candidate.
- **Pilot-to-Final gate:** Required explicit approval after every valid Pilot.
- **Insufficient override:** Explicit selection of an already-declared candidate after insufficiency. It gives up the precision target.
- **Frozen selection:** Candidate ID and exact Final counts. An insufficient outcome beside this selection records the override without a separate flag.

See [approval and override](evaluation-methodology.md#explicit-approval-and-insufficient-override).

## Workflow and deployment

- **Gust:** The workflow engine for static task scheduling, retries and persisted run/task results.
- **DAG:** A directed acyclic graph of named tasks and dependencies.
- **ScatterGather:** The retained trial executor, local or RabbitMQ-backed according to configuration.
- **Mapped task:** A task expanded over an upstream work list.
- **Fan-in:** A downstream stage that validates and combines all expected mapped results.
- **Phase contract:** Strict JSON transport for one native phase's root input and terminal output.
- **Completion proof:** Canonical run/input binding, succeeded status, one succeeded terminal task and valid typed domain output.
- **Evidence snapshot:** One immutable-by-application phase-owned evidence value in PostgreSQL.
- **Prepared snapshot:** Stored evidence before lifecycle acceptance; its presence alone proves no acceptance.
- **Acceptance witness:** The locked state transition and successor phase that authorize downstream work.
- **Caller-owned continuation:** The Workflow loop run by a Study caller to the next approval/terminal boundary.
- **RunMonitor:** A wait-only service that polls durable Gust/execution state, including separate-VM cancellation.
- **Configured environment label:** The operator assertion frozen at creation and rechecked at Final boundaries. It is not an authenticated fingerprint.

## Study lifecycle

- **Study definition:** Native YAML declaring identity, one seed, family settings, shared policies, tier inputs and ordered candidates.
- **Normalized study revision:** The resolved immutable typed definition; source YAML text and unknown keys are excluded.
- **Public Revision:** The study ID/revision-number value returned by creation and accepted by `Study.start/1`.
- **Study execution:** One attempt to run a frozen revision with its own physical effects.
- **Lifecycle state:** One of `collecting_pilot`, `analyzing_pilot`, `awaiting_final`, `collecting_final`, `analyzing_final`, `succeeded`, `failed`, `cancelled`.
- **Study phase:** One of the four fixed collection/analysis phases in an execution.
- **PhaseRun:** One canonical application link to a Gust run. Pilot/analysis use `:single`; Final Collection uses tier keys.
- **CollectionPlan:** One immutable ordered resolved request set per PhaseRun.
- **CollectionItem:** One replica/item coordinate owning unique optimization and experiment reservations.
- **Warm-up replica:** Excluded position `-1`, before a tier's five measured replicas.
- **Measured replica:** Position `0..4`, with fixed scientific inputs and fresh physical effects.
- **Scientific equality:** Equality of meaningful inputs, actions, settings, seeds and outcomes, excluding generated IDs and timing.
- **Representative Final evidence:** Measured position zero after all five positions pass equality.
- **Clock session:** A transient tier-bound identity for ordered monotonic readings.
- **Completed duration receipt:** Durable plan-selection/simulation/total microseconds for one measured replica.
- **Timing summary:** Five measured triplets per tier; helpers derive the median and observed range.
- **Compact study result:** Public execution/revision identity, Pilot outcome, frozen selection, corrected family and raw measured timing after success.
- **Task retry:** Another attempt within the same Gust run, reusing reserved effects for its CollectionItem.
- **Re-entry:** A new caller's continuation through canonical existing work and durable receipts.
- **Phase replay:** Starting a replacement phase attempt inside one execution; no supported API provides this.

The [overview](evaluation-study-overview.md) describes states, approval, waiting and cancellation.
