# Scope, Assumptions, and Limits

This page defines the study's model, evidence, and interpretation boundaries.

## Research questions

The main research question is:

> In controlled network topologies, how do equal-action-count defense
> strategies differ from CVSS prioritization in their effect on simulated
> mission impact?

The study also asks:

1. How does a pre-attack feasibility constraint change selected defense plans
   and modeled mission disruption before an attack?
2. How does controlled topology growth affect simulation runtime,
   plan-selection runtime, and mission-impact differences between each defense
   strategy and CVSS prioritization?

Simulated mission impact is the primary outcome. Blast radius is a secondary
safety outcome.

## Model assumptions

The model is a discrete stochastic state-transition simulation. It represents
hosts, services, vulnerabilities, network segments, credentials, reachability
policy, and mission capabilities in one context graph.

Each experiment uses:

- one fixed graph revision;
- one policy and attacker model;
- one declared initial foothold;
- a finite action-step limit; and
- an action-count budget.

Each defense action has unit cost. The author approved equal maximum caps of one, two and three.
Early stopping is allowed. Report actual action use and selected targets for every plan.
Comparisons therefore concern selection policies under equal caps; realized plan lengths can differ.

At each attack step, the simulator selects uniformly from eligible actions. It
then samples the selected action's outcome from the vulnerability's scenario
probability.

## Evidence sources

Evidence comes from the built-in synthetic vulnerability catalog or a reviewed
static subset of NVD data. The study records the selected source.

The baseline uses fixed synthetic topologies to isolate strategy, budget,
feasibility, and topology-size effects. Estimates remain conditional on those
topologies.

Pilot observations select sample sizes. Final analysis uses freshly collected
observations for confirmation.

## Implemented evaluation scope

The [study overview](evaluation-study-overview.md) describes the public operations
and current limits. Native Evaluation2 covers:

- one mission-impact comparison per declared tier, budget and alternative versus implicit CVSS;
- fixed-sample matching-based bounded-mean inference under the declared IID-input model;
- one Holm correction across the complete primary family;
- a Precision Pilot that selects common plan and attack counts;
- fresh, separate Final evidence after explicit approval;
- a required pause after every valid Pilot outcome; and
- one durable successful result.

The [YAML constructor](../evaluation2.md#input-contract) checks required known fields and drops unknown keys.
It resolves immutable graph/Host inputs and freezes shared model settings, ordered candidates, one seed and derived contracts.
The stored definition excludes source YAML text.
Changed scientific inputs require a new revision.

The thesis study adds an explicit scientific check before Pilot, before fresh Final observations and after Final analysis.
It requires the complete 36-member family, positive model ranges and the one-point precision target.
A zero-range scenario or collapsed interval requires investigation. A wide Final stays visibly imprecise under its frozen counts.
The paired feasibility procedure remains descriptive and outside the primary family.
See [scientific study admission](evaluation-methodology.md#9-scientific-study-admission).

Research use requires accepted model and method assumptions.
The native protocol is verified at small counts. The complete [prespecified calibration](../history/evaluation2-calibration-20261031.md) passed its declared model-grid checks.

## Operational timing scope

Operational timing collection is implemented. Final collection runs tiers
sequentially. Each tier has excluded warm-up `-1` and measured replicas `0..4`.
The configured observed environment assertion must match the revision before
warm-up, before replica `0`, at each shared boundary between adjacent measured
replicas, and after replica `4`.

The application-supervised clock measures plan selection, simulation and their total in one session.
The shared plan-completion/simulation-start boundary makes total equal the sum of its components.
Gust stores completed duration receipts. Final Collection checks all five measured scientific evidence sets before preparing replica-zero evidence.
Persistence separately owns acceptance. Timing replicas do not increase inferential sample size.

The result stores five measured microsecond triplets per tier.
Helpers derive medians and observed ranges from those values.
Raw monotonic readings stay in memory. Detailed evidence stays in PostgreSQL and domain records.

The [verification record](../history/evaluation2-verification.md) preserves two real service-backed successful local studies.
Both used small counts and insufficient-Pilot overrides. They establish the protocol, rather than useful precision, power or calibration.
Caller-owned continuation and durable polling support bounded re-entry and separate-VM cancellation.
Lost incomplete clock sessions fail without replacement measurements.
There is no automatic background lifecycle recovery or phase-replay API.
Deployment remains subject to the [runtime requirements](../infrastructure.md#native-evaluation2-runtime) and operator authorization.

## Pilot-to-Final boundary

A valid Pilot always leads to a pause.

- When the Pilot recommends a candidate, Final uses that candidate.
- When the Pilot is insufficient, the operator can explicitly select one already-declared candidate.
  The insufficient outcome beside the frozen selection records that override.
- Invalid or failed Pilot work supplies no approval outcome.

An override gives up the precision target.
Final intervals can remain wide and tests can have low power.
Valid fresh-Final inference still requires the fixed family, independent phase inputs and frozen procedure.
Holm controls family-wise false rejection only under valid marginal inference.

## Open research questions

The results are conditional on the declared graphs, policies, attacker model,
budgets, seeds, and measured environment. The study leaves these topics open:

- observed attacker behavior and exploit likelihood;
- effectiveness in enterprise networks;
- cost comparison between equal-action-count plans;
- deployable cost-aware segmentation;
- population-level behavior across graph designs; and
- performance in other environments.
