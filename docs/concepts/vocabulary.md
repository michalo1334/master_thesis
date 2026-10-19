# Vocabulary

Terms shared across the documentation. Use them consistently in the documentation and the thesis. Definitions are
concise. Each term's model page states its precise semantics.

For the scientific rules, read the [evaluation methodology](evaluation-methodology.md). For the implemented software, read
the [evaluation pipeline](../inprogress/evaluation-pipeline.md).

## Graph

- **Graph**: A network context model of nodes and edges. It has an immutable
  revision history.
- **Graph revision**: One immutable snapshot of a graph.
- **Optimized graph revision**: The new graph revision an optimization run
  creates after it applies its selected defense actions.

## Simulation

- **Simulation**: A Monte Carlo experiment on one graph revision.
- **Experiment**: The persisted record of one simulation and its trials.
- **Trial**: One independent attacker trajectory in a simulation.
- **Iteration**: One attacker action step within a trial.
- **Simulation seed**: The deterministic random input for a simulation. Each trial derives its own seed from the
  simulation seed. This term covers simulation only. Evaluation workflows use the seed terms below.
- **Baseline simulation**: The simulation on the source graph revision before
  defense.
- **Blast radius**: The number of foothold hosts at the end of a trial,
  including the initial foothold.
- **Mission impact**: The weighted impact of mission capabilities disrupted at
  the end of a trial.
- **Modeled pre-attack mission disruption**: Required-flow or mission-support
  loss caused by a defense plan before attacker footholds are applied.

## Optimization

- **Defense action**: One change selected to reduce modeled attack impact.
- **Strategy**: The method that selects defense actions under a budget.
- **Plan**: The actions selected by one strategy for one budget and selection
  seed.
- **Budget**: The maximum number of defense actions an optimization run may
  apply. Equal budgets compare action counts, not money, effort, deployment
  complexity, or operational risk.
- **Null strategy**: A descriptive no-defense control.
- **Pre-attack feasibility**: The condition where each mission capability is
  operational before attacker footholds are applied.

## Evaluation and study

- **Evaluation**: A statistical comparison of alternative and reference strategy outcomes. One evaluation is one
  comparison or one declared family of comparisons.
- **Comparison**: One alternative strategy measured against one reference strategy, for one tier, one budget, and one
  outcome. Stage 2 and Stage 3 report an estimate, an interval, and a raw p-value for it. The Pilot evaluates a candidate
  against it and reports precision only.
- **Reference strategy**: The strategy that a comparison measures against. The study design uses CVSS prioritization as
  the reference. The no-defense control is not this reference.
- **CVSS prioritization**: The reference strategy for the study comparisons. CVSS is the Common Vulnerability Scoring
  System. This strategy orders defense actions by CVSS severity. It is not the no-defense control.
- **Family**: A declared set of comparisons. Stage 3 applies one Holm correction across the family. The Pilot uses the
  family for precision checks and applies no correction.
- **Primary family**: The declared family that supports the primary claim. It excludes controls, secondary outcomes, and
  exploratory comparisons unless the study declares them as members.
- **Identity**: The five fields `(tier, budget, alternative, reference, outcome)` that name one comparison.
- **Estimand**: The quantity that the method estimates. For one comparison it is the difference between the mean
  alternative and reference mission impacts.
- **Declared order**: The array order in a request or snapshot. Declared order defines tier rank and occurrence order.
  JSON object key order never does.
- **Interval**: The corrected crossed-bootstrap percentile interval for the mean effect, at the declared confidence
  level.
- **Half-width**: Half the interval width, `(upper - lower) / 2`. The Pilot uses the half-width as its precision
  measure.

## Evidence and sampling

- **Evidence matrix**: One side of a comparison. Rows are selected plans and columns are shared attack columns.
- **Plan-selection replicate**: One selected plan for a strategy, budget, and selection seed. Each plan provides one
  matrix row.
- **Attack column**: One attack seed shared by every plan in a crossed comparison. Both sides use the same ordered
  columns.
- **Column alignment**: The rule that all plans in one comparison cover the same ordered attack columns. Unequal
  coverage is an error, not a gap to fill.
- **Outer subsample**: One selection of plan rows and attack columns without replacement from Pilot evidence.
- **Inner bootstrap**: The resampling inside the crossed bootstrap. It draws rows and columns with replacement. Outer
  subsampling never uses replacement.
- **Non-informative comparison**: A comparison whose estimate and interval limits are numerically zero. Stage 2 and
  Stage 3 report `assessment.status = non_informative` and a raw p-value of one. A Pilot candidate response reports
  `informative = false`. In a Pilot, one non-informative outer subsample makes the comparison non-informative.
- **Zero-width interval**: An informative result with numerically equal interval limits. Stage 2 and Stage 3 report it
  through the `assessment.warnings` entry `zero_width_interval`. It is not proof of equivalence.

## Seeds and randomness

Evaluation uses two kinds of randomness. **Collection randomness** decides which plans and attack trials produced an
observed value. **Analysis randomness** drives the rows, columns, and resamples inside a calculation. The Pilot outer
subsampling is analysis randomness. Keep the two kinds separate, because they answer different questions.

- **Plan-selection seed**: The seed that selects one plan for a strategy, budget, and replicate. It belongs to
  collection randomness.
- **Attack seed**: The seed that drives one attack trial on a selected plan. It belongs to collection randomness.
- **Resampling seed**: The seed that a Stage 2 comparison request, or one Stage 3 member request, declares for the
  analysis calculation. It belongs to analysis randomness.
- **Pilot base seed**: The declared seed in the Pilot sampling settings. Stage 4 derives every comparison stream seed
  from it.
- **Comparison stream seed**: The Stage 4 seed for one declared comparison. It is the base seed plus a tier-rank offset
  plus an occurrence offset. The [pipeline](../inprogress/evaluation-pipeline.md#seeds) states the derivation and
  [Stage 4 overview](../inprogress/evaluation-stage-4-overview.md#scientific-method) states the fixed child-stream
  contract.

## Statistics

- **Corrected crossed bootstrap**: The accepted interval method. It resamples rows and shared columns with replacement
  and applies the historical finite-sample correction.
- **Centered crossed bootstrap**: The accepted null method. It centers each side by its own mean, then applies the same
  corrected procedure. The raw p-value is the count of null draws at least as extreme as the estimate, with the accepted
  add-one correction in the numerator and denominator. The [methodology section on the raw
  p-value](evaluation-methodology.md#raw-p-value-centered-crossed-bootstrap) states the formula.
- **Raw p-value**: The per-comparison p-value before family correction.
- **Adjusted p-value**: The p-value after the declared family correction.
- **Holm correction**: The family correction that orders raw p-values and enforces monotonicity. It changes p-values
  only. Estimates and intervals stay per-comparison values.
- **Degeneracy warning**: The methodology term for a zero-width but informative result. The wire contract reports it as
  the `zero_width_interval` warning.

## Precision Pilot

- **Precision Pilot**: The workflow that chooses a common plan count and attacks-per-plan count for Final evidence.
- **Candidate**: One pair of a plan count and an attacks-per-plan count from the declared grid.
- **Candidate grid**: The Cartesian product of the declared plan candidates and attack candidates.
- **Candidate comparison**: One candidate evaluated against one declared family comparison.
- **Outer subsample count**: The number of repeated subsamples for one candidate comparison.
- **Guard quantile**: The quantile of the outer half-widths that sets the guarded width. A high quantile protects
  against a narrow, lucky subsample.
- **Guarded half-width**: The half-width at the guard quantile for one candidate comparison.
- **Worst guarded half-width**: The maximum guarded half-width across the family for one candidate.
- **Recommendation**: The candidate that passes every comparison and wins the declared selection rule.
- **Insufficient Pilot**: The result when no candidate passes. The only implemented reason is `no_passing_candidate`.

## Workflow and deployment

- **Gust**: The Elixir workflow engine that loads DAG files, schedules tasks, retries temporary failures, and persists
  run and task state.
- **DAG**: A fixed directed acyclic graph of named tasks. The repository has one DAG per workflow.
- **Mapped task**: A task that Gust expands once for each item in an upstream task result.
- **Fan-in**: The task that runs after every mapped task succeeds. The Stage 3 fan-in verifies the complete family and
  sends the Holm request. The Stage 4 fan-in verifies the complete grid and selects locally.
- **Preflight**: The pre-run check that builds every Pilot work item and candidate request in memory. A failure in a
  checked condition prevents the Gust run. Preflight does not contact Python.
- **Wire contract**: The checked-in JSON Schema that defines request and response shapes for both runtimes.
- **Read-back**: The typed verification of a persisted task result against its request and declared relations.
  Stage 4 also re-derives the candidate summaries and the recommendation. A succeeded run alone is not sufficient.
- **Resource cap**: A deployment limit on work size. It is configuration, not a scientific setting.
- **Evidence snapshot**: An application-owned JSONB record that holds Pilot evidence. The API creates or reads a
  snapshot. Changed evidence needs a new snapshot ID. No database trigger enforces this rule.
- **Study revision ID**: A UUID that labels the study revision. No durable revision record or foreign key exists yet.
- **Evidence role**: The declared role of evidence. Stage 4 snapshot and Pilot inputs accept `pilot` and reserve
  `final`. Stage 3 prototype requests declare `synthetic_prototype`. Stage 2 comparison requests carry no evidence
  role.
- **Pilot evidence**: Evidence and seeds used to choose sample sizes. Pilot evidence is not Final evidence.
- **Final evidence**: Evidence collected after the Pilot decision with fresh seeds and frozen settings. No public
  workflow produces it yet.
