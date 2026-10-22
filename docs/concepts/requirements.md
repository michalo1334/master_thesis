# Functional Requirements

These requirements define behavior that a user or another system can observe.

## Graph workspace

- The workspace must create a graph.
- The workspace must open a saved graph revision.
- The workspace must save an edit as a new immutable revision.
- A save must identify the base revision that the user edited.
- The workspace must reject a base revision that is unknown or belongs to a
  different graph.
- The workspace must let the user add and remove hosts, services,
  vulnerabilities, network segments, credentials, and mission capabilities.
- The workspace must let the user connect and disconnect nodes with supported
  relationship types.
- The workspace must show the properties of a selected node or relationship.
- The workspace must present topology and network data on one canvas.
- The workspace must place hosts and services inside their network segments when
  the user requests an arrangement.
- Segment membership must stay unchanged when a screen position changes.
- The workspace must list an entity as unplaced when its placement is missing or
  ambiguous. It must give a reason.
- The workspace must let the user keep several graphs open and switch between
  them.

These rules protect revision identity and keep graph meaning separate from
screen layout.

## Attack simulation and reporting

- The system must run a Monte Carlo simulation on one graph revision.
- The user must be able to set the trial count, iteration limit, random seed,
  and maximum attempts per action.
- The system must verify that the initial foothold identifies a graph host and
  reject an invalid value.
- The system must verify pre-attack mission feasibility and reject a failed
  check.
- At each iteration, the system must select one eligible action uniformly at
  random and then sample that action's outcome.
- The system must stop a trial when the iteration limit is reached or the
  eligible action set is empty.
- For a completed experiment, the system must report the mean, median, p95,
  p99, minimum, maximum, and variance of blast radius and mission impact.
- The system must report the compromise probability of each host.
- The system must report the status of each mission capability.
- The system must report traversal probability for each supporting graph
  relationship.

The selection rule and the outcome probability must remain separate. This
prevents a high-probability action from also receiving an unintended selection
advantage.

## Defense optimization

- The user must be able to optimize one graph revision with a selected strategy,
  objective, and maximum action budget.
- The system must support patching a vulnerability, blocking a segment policy,
  and revoking a credential.
- The system must apply at most the configured number of actions.
- When feasibility is required, the system must reject an action that disrupts
  any mission capability before the attack.
- The system must save the optimized graph as a new revision.
- The saved result must identify the selected actions, used budget, and runtime.
- The system must support null, random, CVSS, topology-segmentation,
  simulation-informed, and simulated-annealing strategies.

The feasibility rule prevents an optimizer from improving attack outcomes by
breaking the mission before the attack starts.

## Evaluation analysis

- One comparison must use aligned alternative and reference evidence matrices.
- A comparison must return an effect estimate, a corrected crossed-bootstrap
  interval, and a raw p-value.
- A family analysis must require each declared comparison exactly once.
- A family analysis must apply one Holm correction across the complete family.
- Pilot and Final evidence must use separate immutable snapshots.
- A Precision Pilot must evaluate every declared sample-size candidate against
  every declared family comparison.
- The Pilot must return either one recommendation or an explicit insufficient
  outcome.
- A Final analysis must use the sample counts selected after the Pilot.
- A Final analysis must reject a different study identity, family, comparison
  order, or selected count.
- A Final analysis must return one validated complete-family result with one
  Holm correction.
- Evidence snapshots must hold the matrices. Workflow results must hold compact
  derived values and references.

These rules keep the sampling units intact and prevent a partial family from
receiving a misleading multiplicity correction.

## Study definition and execution

- A study definition must use versioned YAML input.
- Parsing must reject duplicate or unknown keys, aliases, merges, tags,
  non-string map keys, unsafe JSON values, environment interpolation, and
  secrets.
- The system must normalize valid YAML to immutable JSON-compatible data.
- The normalized definition must reference immutable domain revisions.
- The study definition must supply every scientific setting explicitly.
- One execution must move through explicit validation, Pilot collection, Pilot
  analysis, the Pilot-to-Final pause, Final collection, Final analysis, and a
  terminal state.
- Pilot and Final collection must use separate fixed DAGs.
- Collection tasks must call the simulation API. ScatterGather must own the
  trial batches inside each simulation.
- The execution must always pause after a valid Pilot analysis.
- When the Pilot recommends a candidate, resume must use that candidate.
- When the Pilot is insufficient, resume must require manual selection of one
  candidate already declared in the study definition. The result must record
  `pilot_override: true`.
- An invalid, failed, partial, or exhausted Pilot must enter the terminal failed
  state.
- Resume must collect fresh Final observations.
- Each phase may run more than once. The execution must retain every attempt and
  identify the one accepted result.
- A successful study must create one immutable compact result. It must include
  accepted phase references, the Pilot outcome, the selected candidate, the
  override marker, and the validated Final family result.

The explicit pause separates sample-size selection from confirmatory evidence
collection. Retaining every attempt supports at-least-once execution without
claiming exactly-once behavior.
