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
- A comparison must return the all-cell mean contrast, a pointwise matching-based bounded-mean interval and a valid marginal p-value under the declared IID-input model.
- Counts, logical order, tuning and family membership must freeze before fresh Final evidence.
- Empirical zero spread must retain uncertainty unless the graph model has zero outcome range.
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

- A study definition must use the native YAML constructor through `NetworkDefense.Evaluation2.Study`.
- The constructor must check required known fields and drop unknown keys.
- Study input must contain no credentials. Environment-like text is literal input, rather than a secret-resolution mechanism.
- The system must normalize valid YAML to immutable JSON-compatible typed data.
- The constructor must resolve graph revisions and Host foothold membership before freezing.
- One seed, shared defense/simulation policies and fixed tier slots must determine derived groups, comparisons, capacity, policies and seeds.
- The definition must record method/seed contracts and the configured measurement label.
- Input changes must require a new revision; legacy formats have no compatibility reader.
- One execution must move through explicit validation, Pilot collection, Pilot
  analysis, the Pilot-to-Final pause, Final collection, Final analysis, and a
  terminal state.
- Pilot and Final collection must use separate fixed DAGs.
- Collection tasks must call the simulation API. ScatterGather must own the
  trial batches inside each simulation.
- The execution must always pause after a valid Pilot analysis.
- When the Pilot recommends a candidate, resume must use that candidate.
- When the Pilot is insufficient, resume must require explicit selection of one already-declared candidate.
- The result must retain the insufficient Pilot outcome beside the frozen selection. These values record the override without a separate boolean.
- An invalid, failed, partial, or exhausted Pilot must enter the terminal failed
  state.
- Resume must collect fresh Final observations.
- Each fixed phase has at most one persisted row per execution. Pilot collection
  and each analysis phase accept one Gust run. Final collection accepts an
  ordered family of tier runs, one per declared tier.
- Final collection must run tiers sequentially. Each tier must run excluded
  warm-up `-1` before measured replicas `0..4`.
- The configured observed environment assertion must match the revision before
  warm-up, before replica `0`, at each shared boundary between adjacent measured
  replicas, and after replica `4`. A missing or different assertion must fail
  collection.
- The application-supervised clock must measure plan selection, simulation and total in one session per tier.
- The shared handoff marker must make total equal the sum of plan-selection and simulation durations.
- Gust must store all five measured duration triplets. Raw monotonic readings must remain transient.
- A lost incomplete clock session must fail without invented or replacement measurements.
- Five measured scientific evidence sets must match before replica `0` alone supplies representative Final evidence.
- Final Collection must prepare the snapshot; Workflow must request lifecycle acceptance from Persistence separately.
- A prepared snapshot alone must not authorize Final Analysis.
- Gust task retries must reuse each item's reserved effects, without an exactly-once computation claim.
- Caller-owned continuation must use canonical linked runs and prove terminal completion before acceptance.
- RunMonitor must remain wait-only and observe cancellation through durable state across command VMs.
- A finite API timeout must return Status without cancellation or Final approval.
- Cancellation must commit before best-effort stopping. Late completion must preserve terminal state.
- Completed tier timing must remain reconstructable after caller/clock loss.
- The system provides no phase-replay API, replacement replicas or automatic background lifecycle recovery.
- A successful execution must own one immutable result, inserted atomically with success.
- The public result must include execution/revision identity, Pilot outcome, frozen selection, complete corrected family and five timing triplets per tier.
- Timing helpers must derive medians and observed ranges from the stored raw values.
- Internal phase/Gust/snapshot links and detailed evidence must remain with their durable owners.
- Native commands must start the normal application; execution commands require dispatch-capable Gust.
- Create, inspect and cancel commands must not dispatch unrelated queued Gust work.
- Full calibration and legacy deletion must follow the documentation gate, with a repeated documentation audit after deletion.

The explicit pause separates sample-size selection from confirmatory evidence
collection. Gust task retries allow work to execute more than once inside a run;
they do not provide exactly-once computation or phase replay.
