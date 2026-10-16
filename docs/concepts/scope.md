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
2. How does controlled growth in topology size affect simulation and
   plan-selection runtime, and the mission-impact contrasts between
   equal-action-count strategies and CVSS prioritization?

Simulated mission impact is the primary outcome. Blast radius is a secondary
safety outcome.

## Model bounds and assumptions

The model is a discrete, stochastic, state-transition simulation of attack
propagation over a graph of hosts, services, vulnerabilities, network segments,
and mission capabilities.

Current bounds:

- one fixed topology, policy, and attacker model per experiment;
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

## Evidence boundary and data-source status

The built-in catalog contains synthetic vulnerability entries. The baseline
scenario can also use a reviewed static NVD subset. Each vulnerability has a
scenario success probability. This probability is a scenario parameter, not a
measured exploit rate.

NVD ingestion is deferred and is **not implemented**. No runtime process
fetches NVD or another external vulnerability source.

The current baseline topology is a fixed, hand-authored scripted scenario. The
[preserved methodology](evaluation-methodology.md) records the research method
for a later clean implementation.
