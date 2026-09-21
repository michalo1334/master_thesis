# Scope, Assumptions, and Limits

This document states the boundaries of the master's thesis project. The thesis
holds the full research narrative. This page does not repeat it.

## Research questions

Main research question:

> Within controlled stylized network topologies, how do equal-action-count
> defense strategies differ from CVSS prioritization in reducing simulated
> mission impact?

Sub-questions:

1. How does a pre-attack feasibility constraint change selected defense plans
   and directly measured operational loss?
2. How does controlled growth in topology size affect simulation,
   strategy-selection, and total-evaluation runtime, and the mission-impact
   ranking of equal-budget defense strategies?

Mission impact is the primary outcome. Blast radius is a secondary safety
outcome.

## Model bounds and assumptions

The model is a discrete, stochastic, state-transition simulation of attack
propagation over a graph of hosts, services, vulnerabilities, network segments,
and mission capabilities.

Current bounds:

- one fixed stylized topology, policy, and attacker model;
- equal-action-count budgets only (each current defensive action has unit cost);
- a finite horizon of attacker action steps per trial;
- attacks start from a declared entry host.

The simulator selects uniformly from eligible actions and then samples the
selected action's outcome. It does not estimate real-world exploit likelihood.

The model cannot substantiate claims about real lateral movement, deployable
cost-aware segmentation, real-world exploit likelihood, or general scalability
beyond measured scenarios.

## Approved topology-scale study

The approved study is a research design, not current implementation. It uses
three controlled size tiers. A runtime pilot will select their exact sizes before
the full study. This page does not prescribe how the variants will be
constructed. Variants preserve roles, edges, exposure, reachability patterns,
attacker context, and equal budgets.

Current code supports the fixed baseline scenario and generic generated topology
sources. It can freeze a generated topology source into an immutable graph
revision. The cloud study is blocked until the planned tooling exists (see the
[cloud evaluation tooling plan](../inprogress/cloud-evaluation-tooling-plan.md)).

Local rehearsal work informed the cloud-study plan. It does not support cloud
runtime, topology-scale, optimizer-quality, or strategy-effect claims. Such
claims require the completed cloud study.

The cloud study requires fixed-environment evidence. Future tooling records
that evidence automatically before the study starts.

The study freezes variants, graph data, metrics, strategies, budgets, seeds,
trial count, and stopping rules before the full study begins. It adds no
directional hypothesis.

## Compared methods

The approved full-study matrix will compare defensive methods under shared
action budgets of one through three:

- random defense selection;
- CVSS (vulnerability-score) priority ordering;
- topology-driven policy segmentation;
- simulation-informed patching;
- simulated-annealing search over patching and segmentation actions.

The matrix will use equal budgets and multiple fixed selection seeds. A
mission-impact pilot will choose the attack-trial count before the full study.
Current baseline experiments use a budget-one subset of this strategy matrix.

## Outcome metrics

The full study will report expected mission impact and strategy ranking. Blast
radius is its secondary safety outcome. It will also report direct pre-attack
feasibility, including unavailable required flows and affected mission
capabilities.

The full study will report median simulation, strategy-selection, and
total-evaluation durations on a fixed documented environment after warm-up.
The fixed environment record is a future tooling prerequisite: no automatic
environment record exists yet (see the
[cloud evaluation tooling plan](../inprogress/cloud-evaluation-tooling-plan.md)).

It will also report host compromise probabilities and per-capability disruption
status.

## Evidence boundary and data-source status

The built-in catalog contains synthetic vulnerability entries. The baseline
scenario can also use a reviewed static NVD subset. Each vulnerability has a
stylized success probability. This probability is a scenario parameter, not a
measured exploit rate.

NVD ingestion is deferred and is **not implemented**. No runtime evaluation
fetches NVD or another external vulnerability source.

The current baseline topology is a fixed, hand-authored scripted scenario. A
command-line evaluation runner executes a saved
manifest, persists plans and results, and writes result artifacts for later
statistical analysis. The reproducible evaluation runner and versioned result
artifacts are the precondition for any sensitivity or scalability claim (see
sub-question 2).
