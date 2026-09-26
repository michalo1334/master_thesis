# Scope, Assumptions, and Limits

This document states the boundaries of the master's thesis project. The thesis
holds the full research narrative. This page does not repeat it.

## Research questions

Main research question:

> Within controlled network topologies, how do equal-action-count
> defense strategies differ from CVSS prioritization in reducing simulated
> mission impact?

Sub-questions:

1. How does a pre-attack feasibility constraint change selected defense plans
   and modeled pre-attack mission disruption?
2. How does controlled growth in topology size affect simulation,
   plan-selection, and total-evaluation runtime, and the mission-impact
   contrasts between equal-action-count strategies and CVSS prioritization?

Simulated mission impact is the primary outcome. Blast radius is a secondary
safety outcome.

## Model bounds and assumptions

The model is a discrete, stochastic, state-transition simulation of attack
propagation over a graph of hosts, services, vulnerabilities, network segments,
and mission capabilities.

Current bounds:

- one fixed topology, policy, and attacker model;
- equal-action-count budgets only;
- a finite horizon of attacker action steps per trial;
- attacks start from a declared entry host.

Each current defense action has unit cost. Equal action counts compare plan
cardinality. They do not represent equal money, effort, deployment complexity,
or operational risk.

The simulator selects uniformly from eligible actions and then samples the
selected action's outcome. It does not estimate real-world exploit likelihood.

The model cannot substantiate claims about real lateral movement, deployable
cost-aware segmentation, real-world exploit likelihood, or general scalability
beyond measured scenarios.

## Approved topology-scale study

The approved Azure study is a research design, not current implementation. It
uses three controlled size tiers and one frozen graph per tier. A runtime pilot
selects the exact tier sizes before the full study. The tier designs preserve
the declared role schema, exposure template, reachability policy pattern,
attacker context, and equal-action-count budgets. A diagnostic records how
attack-relevant structure changes as the graph grows.

Current code supports the fixed baseline scenario and generic generated
topology sources. It can freeze a generated source into an immutable graph
revision. The Azure study is blocked until the planned tooling exists (see the
[cloud evaluation tooling plan](../inprogress/cloud-evaluation-tooling-plan.md)).

Local runs are pilots. They validate the workflow and select study parameters.
They do not support final cloud-runtime, topology-scale, optimizer-quality, or
strategy-effect claims. Those claims require the completed Azure study.

The Azure study requires a fixed environment record before measured runs. It
freezes graph data, metrics, strategies, action-count budgets, plan-selection
seeds, attack seeds, sample counts, and stopping rules before final collection.
The study is exploratory and has no directional hypothesis.

## Compared methods

The primary study compares four alternatives with CVSS prioritization:

- random defense selection;
- topology-driven policy segmentation;
- simulation-informed defense selection;
- simulated-annealing search over defense plans.

Each comparison uses equal action-count budgets of one, two, and three. The
null strategy is a descriptive no-defense control. It is not part of the
primary comparison family. A mission-impact pilot selects one common number of
plan-selection seeds and one common number of attacks per plan before final
collection.

## Outcome metrics

The primary estimand is the paired mean difference in simulated mission impact
between each alternative and CVSS. Results order strategies by these contrasts
within each tier and budget. This order is not a universal total ranking.

Blast radius is the secondary safety outcome. It counts all foothold hosts at
the end of a trial, including the initial foothold. The study also reports
modeled pre-attack mission disruption through unavailable required flows and
affected mission capabilities.

Primary intervals must include plan-selection variation and attack-outcome
variation. The precision target is a confidence-interval half-width of one
mission-impact point. Holm correction applies once across the 36 primary
comparisons: four alternatives, three budgets, and three tiers.

Each tier has one excluded warm-up and five accepted measured Azure replicas.
The study reports the median and observed range of simulation, plan-selection,
and total-evaluation durations from one recorded environment. Automatic
environment recording remains planned tooling (see the
[cloud evaluation tooling plan](../inprogress/cloud-evaluation-tooling-plan.md)).

The study also reports host compromise probabilities and per-capability
disruption status.

## Evidence boundary and data-source status

The built-in catalog contains synthetic vulnerability entries. The baseline
scenario can also use a reviewed static NVD subset. Each vulnerability has a
scenario success probability. This probability is a scenario parameter, not a
measured exploit rate.

NVD ingestion is deferred and is **not implemented**. No runtime evaluation
fetches NVD or another external vulnerability source.

The current baseline topology is a fixed, hand-authored scripted scenario. A
command-line evaluation runner executes a saved
manifest, persists plans and results, and writes result artifacts for later
statistical analysis. The reproducible evaluation runner and versioned result
artifacts are the precondition for any sensitivity or scalability claim (see
sub-question 2).
