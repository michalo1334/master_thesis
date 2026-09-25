# Functional Requirements

This page describes current, externally observable behavior only. It states no
plans and no non-functional constraints. Code and tests define behavior.

## Graph workspace

- The workspace shall create a new graph.
- The workspace shall open an existing graph revision from the database.
- The workspace shall save the active graph as a new immutable revision, given
  a valid base revision; while the base revision is unknown or belongs to a
  different graph, the workspace shall reject the save.
- The workspace shall let the user add and remove nodes of the supported types:
  host, service, vulnerability, network segment, credential, and mission
  capability.
- The workspace shall let the user connect and disconnect nodes with the
  supported relationship types.
- The workspace shall let the user inspect the properties of a selected node or
  edge.
- The workspace shall show one topology canvas; the workspace shall not offer
  separate topology and network views.
- The workspace shall place hosts and services inside their network segments
  when the user requests an arrangement.
- The workspace shall keep placement and geometry separate: a position change
  shall not change segment membership.
- While an entity has no unambiguous placement, the workspace shall list it as
  unplaced with a reason.
- The workspace shall let the user keep several graphs open and switch among
  them.

## Attack simulation and reporting

- The system shall run a Monte Carlo simulation on one graph revision.
- The user shall configure the trial count, the iterations per run, the seed,
  and the maximum attempts per action.
- While the initial foothold does not identify a host in the graph, the system
  shall reject the simulation.
- While the graph is not pre-attack mission-feasible, the system shall reject
  the simulation.
- The system shall select an action uniformly from the eligible actions for a
  run, then sample that action's outcome probabilistically.
- The system shall report, for a completed experiment, statistics for blast
  radius and mission impact: mean, median, p95, p99, minimum, maximum, and
  variance.
- The system shall report the compromise probability of each host.
- The system shall report the status of each mission capability.
- The system shall report traversal probability for each supporting graph edge.

## Defense optimization

- The user shall run an optimization against a graph revision with a selected
  strategy and a maximum action budget.
- The system shall apply the supported defense actions: patch a vulnerability,
  block a segment reachability policy, and revoke a credential.
- The system shall not apply more actions than the configured budget allows.
- While the strategy is feasibility-constrained, the system shall reject a
  candidate action that makes any mission capability infeasible before an
  attack.
- The system shall persist the output as a new optimized graph revision, along
  with the selected actions, the used budget, and the runtime.
- The system shall support the strategies: null, random, CVSS, topology
  segmentation, simulation-informed, and simulated annealing.

## Evaluation and result analysis

- The system shall execute an evaluation from a saved manifest that declares
  strategies, budgets, model variants, and a seed schedule.
- The system shall derive one shared attack seed stream that the baseline and
  every post-defense experiment use.
- The system shall run one baseline experiment and one post-defense experiment
  per selected plan against the shared schedule.
- The system shall persist each plan and experiment; while a partially
  completed run resumes, the system shall reuse its persisted plans and
  experiments instead of duplicating them.
- The system shall write a result archive for statistical analysis after an
  evaluation run completes.
