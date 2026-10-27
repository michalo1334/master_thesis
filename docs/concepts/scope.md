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

Each defense action has unit cost. Equal budgets compare plan cardinality.

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
and current limits. The implemented prototype covers:

- one alternative-versus-CVSS comparison for each declared tier, budget,
  strategy, and outcome;
- a corrected crossed bootstrap for each comparison;
- one Holm correction across the complete primary family;
- a Precision Pilot that selects common plan and attack counts;
- separate Pilot and Final evidence collection;
- a required pause before Final collection; and
- one compact immutable study result.

The study definition uses strict versioned YAML. It references immutable domain
revisions and declares the scientific settings, ordered Pilot candidates,
comparison family, seeds, and pause policy. After parsing, the system stores the
normalized definition and discards the input text.

The default lifecycle begins after optimizer calibration, topology construction,
and other pilot work have accepted scientific contracts.

## Operational timing scope

Operational timing collection is implemented. Final collection runs tiers
sequentially. Each tier has excluded warm-up `-1` and measured replicas `0..4`.
The configured observed environment assertion must match the revision before
warm-up and before and after each measured replica.

The coordinator measures plan-selection, simulation, and total elapsed intervals
in its own process. It validates timing values in memory. Five complete-family
non-timing summaries must match before replica `0` alone supplies the Final
snapshot. Other replicas do not increase the inferential sample size.

The compact result stores five measured microsecond values, the median, the
observed minimum, and the observed maximum for each tier and duration type. Raw
monotonic readings and interval boundaries are not persisted. Detailed evidence
stays in PostgreSQL snapshots and runtime records.

Timing collection does not change the outcome method or authorize real-study
values, real evidence collection, or deployment. Current verification uses
synthetic evidence. The prototype adds no replacement replica, automatic
recovery, replay, polling, PubSub, or Oban lifecycle handoff.

## Pilot-to-Final boundary

A valid Pilot always leads to a pause.

- When the Pilot recommends a candidate, Final uses that candidate.
- When the Pilot is insufficient, a user can select one candidate that the
  study definition already declared. The result records
  `pilot_override: true`.
- An invalid or failed Pilot enters the terminal failed state.

After an override, the Pilot outcome remains insufficient. Precision can remain
poor, intervals can remain wide, raw p-values can remain unstable, and manual
selection can introduce bias. Holm correction controls familywise error while
evidence strength continues to depend on sampling precision.

## Open research questions

The results are conditional on the declared graphs, policies, attacker model,
budgets, seeds, and measured environment. The study leaves these topics open:

- observed attacker behavior and exploit likelihood;
- effectiveness in enterprise networks;
- cost comparison between equal-action-count plans;
- deployable cost-aware segmentation;
- population-level behavior across graph designs; and
- performance in other environments.
