# Vocabulary

This page defines the main terms for the network model, simulation, evaluation,
and study workflow. Use one term for one meaning. The
[evaluation methodology](evaluation-methodology.md) gives the statistical rules
and formulas.

## Graph

- **Graph:** A network context model made of typed nodes and directed
  relationships.
- **Graph revision:** One immutable version of a graph.
- **Optimized graph revision:** A graph revision that contains the defense
  actions selected by an optimization run.

## Simulation

- **Simulation:** A Monte Carlo experiment on one graph revision.
- **Experiment:** The saved record of one simulation and its trials.
- **Trial:** One attacker trajectory in a simulation.
- **Iteration:** One attacker action step in a trial.
- **Simulation seed:** The deterministic random input for one simulation. Each
  trial derives its own seed from this value.
- **Baseline simulation:** A simulation on the source graph before defense
  actions are applied.
- **Blast radius:** The number of foothold hosts at the end of a trial. It
  includes the initial foothold.
- **Mission impact:** The sum of the impact weights of mission capabilities that
  are disrupted at the end of a trial.
- **Modeled pre-attack mission disruption:** Loss of required flow or mission
  support caused by a defense plan before attacker footholds are applied.

## Optimization

- **Defense action:** One graph change that is selected to reduce modeled attack
  impact.
- **Strategy:** A method that selects defense actions under a budget.
- **Plan:** The actions selected for one strategy, budget, and selection seed.
- **Budget:** The largest number of defense actions that an optimization run can
  apply. It sets plan cardinality.
- **Null strategy:** A no-defense control that selects no actions.
- **Pre-attack feasibility:** The condition in which every mission capability is
  operational before an attack begins.

## Evaluation and study

- **Evaluation:** A statistical analysis of one comparison or one declared
  family of comparisons.
- **Comparison:** One alternative strategy compared with one reference strategy
  for one tier, budget, and outcome.
- **Reference strategy:** The strategy against which an alternative is measured.
  The primary study uses CVSS prioritization.
- **CVSS prioritization:** A strategy that orders vulnerability defenses by
  CVSS severity. It is the primary reference. The null strategy is the
  descriptive control.
- **Family:** A set of comparisons declared before Final analysis.
- **Complete family:** Every declared comparison exactly once. Validation
  rejects missing, duplicate, and unexpected identities.
- **Primary family:** The family that supports the primary claim. The study can
  declare controls, secondary outcomes, or exploratory comparisons as members.
- **Identity:** The five values `(tier, budget, alternative, reference, outcome)`
  that name one comparison.
- **Estimand:** The quantity that a method estimates. Here it is the difference
  between the mean alternative and reference mission impacts.
- **Declared order:** The order of items in a declared array. It sets tier rank
  and occurrence order. JSON object key order is irrelevant.
- **Interval:** The corrected crossed-bootstrap percentile interval for an
  effect estimate at the declared confidence level.
- **Half-width:** Half of an interval's width: `(upper - lower) / 2`.

## Evidence and sampling

- **Evidence matrix:** One side of a comparison. Rows are selected plans and
  columns are shared attack seeds.
- **Plan-selection replicate:** One plan selected for a strategy, budget, and
  selection seed. It supplies one matrix row.
- **Attack column:** One attack seed used across every plan in a crossed
  comparison. The alternative and reference sides use the same ordered columns.
- **Column alignment:** The requirement that all plans in one comparison use the
  same ordered attack columns.
- **Outer subsample:** A Pilot selection of plan rows and attack columns without
  replacement.
- **Inner bootstrap:** The resampling step inside the crossed bootstrap. It draws
  rows and columns with replacement.
- **Non-informative comparison:** A comparison whose estimate and both interval
  limits are numerically zero. Its raw p-value is one. Equivalence needs a
  separate test.
- **Zero-width interval:** An informative interval whose limits are numerically
  equal. This numerical degeneracy receives a warning.

## Seeds and randomness

**Collection randomness** decides which plans and attack trials produce the
observations. **Analysis randomness** controls subsampling and bootstrap
resampling. Keeping them separate prevents the analysis process from changing
the evidence-generation process.

- **Plan-selection seed:** A collection seed that selects one defense plan.
- **Attack seed:** A collection seed that controls one attack trial.
- **Resampling seed:** An analysis seed for one comparison calculation.
- **Pilot base seed:** The declared root seed for Pilot subsampling.
- **Comparison stream seed:** The analysis seed for one declared Pilot
  comparison. It is derived from the Pilot base seed, tier rank, and comparison
  occurrence.
- **Evaluation root:** The value that initializes one tier's attack-related
  collection streams.
- **Phase seed separation:** The rule that Pilot and Final use disjoint
  plan-selection seeds and disjoint evaluation roots.

## Statistics

- **Corrected crossed bootstrap:** The interval method that resamples plan rows
  and shared attack columns with replacement and applies a finite-sample
  correction.
- **Centered crossed bootstrap:** The null method that centers each side by its
  own mean and then applies the corrected crossed bootstrap.
- **Add-one correction:** The addition of one to both the extreme-draw count and
  the total-draw count when calculating a bootstrap p-value. This prevents a
  reported p-value of zero.
- **Raw p-value:** The p-value for one comparison before family correction.
- **Adjusted p-value:** The p-value after family correction.
- **Holm correction:** A step-down family correction that orders and adjusts raw
  p-values while preserving monotonicity. Estimates and intervals remain
  unchanged per-comparison values.
- **Degeneracy warning:** The warning for a zero-width interval with a nonzero
  effect.

The [raw p-value method](evaluation-methodology.md#raw-p-value-centered-crossed-bootstrap)
states the centered-bootstrap formula.

## Precision Pilot

- **Precision Pilot:** The workflow that selects a common plan count and attack
  count for Final evidence.
- **Pilot sample-size candidate:** One ordered item with a stable ID, a plan
  count per side, and an attack count per plan.
- **Candidate comparison:** The evaluation of one candidate against one family
  comparison.
- **Outer subsample count:** The number of repeated outer subsamples for one
  candidate comparison.
- **Guard quantile:** The quantile of the outer half-widths used to guard against
  one unusually narrow subsample.
- **Guarded half-width:** The interval half-width at the guard quantile for one
  candidate comparison.
- **Worst guarded half-width:** The largest guarded half-width across all family
  comparisons for one candidate.
- **Recommendation:** The candidate that passes every comparison and ranks first
  under the declared selection rule.
- **Insufficient Pilot:** A valid Pilot outcome in which every candidate fails
  at least one comparison.
- **Pilot-to-Final gate:** The required pause after Pilot analysis and before
  Final collection.
- **Confirmatory override:** Manual selection of one declared candidate after an
  insufficient Pilot. The Pilot outcome and precision target remain
  insufficient.
- **Pilot override marker:** The `pilot_override` boolean in the compact study
  result. It records that the insufficient-Pilot exception was used.

The [override method](evaluation-methodology.md#insufficient-pilot-confirmatory-override)
states the rules and risks.

## Workflow and deployment

- **Gust:** The Elixir workflow engine that schedules DAG tasks, retries
  temporary failures, and saves run and task state.
- **DAG:** A directed acyclic graph of named tasks and dependencies.
- **ScatterGather:** The simulation executor that divides trials into batches
  and runs them locally or through RabbitMQ.
- **Mapped task:** A task that Gust expands once for each item from an upstream
  task.
- **Fan-in:** A task that runs after all mapped tasks succeed. It combines and
  validates their results.
- **Preflight:** Local validation that builds all planned analysis requests
  before a workflow run contacts the compute service.
- **Wire contract:** A JSON Schema that defines data exchanged between Elixir
  and Python.
- **Read-back:** Validation of a saved task result against its request and
  declared relationships.
- **Resource cap:** A deployment limit on work size, configured independently
  from scientific settings.
- **Evidence snapshot:** An immutable application record that contains Pilot or
  Final evidence matrices.
- **Study revision ID:** The identifier of one immutable normalized study
  definition.
- **Evidence role:** The declared purpose of evidence, such as Pilot or Final.
- **Pilot evidence:** Evidence used to choose sample sizes.
- **Final evidence:** Separate evidence collected after the Pilot decision and
  used for the confirmatory family analysis.
- **Source Pilot:** The Pilot result that supplies the selected counts for Final
  collection and analysis.
- **Caller assertion:** Metadata whose form a boundary validates. Independent
  evidence is needed to establish provenance.

## Study lifecycle

- **Study definition:** Versioned YAML that declares domain revisions,
  scientific settings, ordered candidates, comparison family, seeds, and the
  Pilot-to-Final pause.
- **Normalized study revision:** The immutable JSON-compatible form of a valid
  study definition. It excludes source YAML text and secrets.
- **Study execution:** One attempt to run a study revision through its lifecycle.
- **Lifecycle state:** One explicit state such as Pilot collection, Pilot
  analysis, the Final gate, Final collection, Final analysis, success, failure,
  or cancellation.
- **Study phase:** One fixed collection or analysis phase and its Gust run.
- **Accepted phase result:** The typed result that the ephemeral coordinator
  accepts after Gust completion.
- **Controlled collection:** Evidence collection through role-specific domain
  APIs, phase runs, item IDs, and declared seed schedules.
- **Ephemeral coordinator:** One supervised application task that advances an
  execution until the Final gate or a terminal state. It does not restart or
  reconnect automatically after an application restart.
- **Compact study result:** An immutable successful record with accepted phase
  references, selected counts, the Pilot outcome, the override marker, and the
  compact Final family result. Evidence matrices remain in their snapshots.
- **Gust task retry:** Gust can repeat a task inside one persisted phase run.
  Application collection items make repeated domain effects safe.
- **Replay:** A new execution of a saved study revision. The prototype has no
  automatic replay policy.
