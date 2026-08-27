# Topology-Scale Study Protocol

Question: how does controlled growth in topology size affect simulation,
strategy-selection, and total-evaluation runtime, and the mission-impact ranking
of equal-budget defense strategies?

See the [scope page](../concepts/scope.md) for the research boundary.

## Status

This study is an approved research design. Current code supports the fixed
baseline scenario and generic topology sources. The controlled variants are not
implemented as frozen study inputs.

## Size tiers

The study uses three controlled size tiers. A runtime pilot selects their exact
host and edge counts before the full study.

The tiers span small, medium, and large topologies. Growth in size must not
change the invariants.

## Invariants

Each tier preserves:

- roles of nodes and edges;
- exposure pattern;
- reachability pattern;
- attacker context;
- equal action-count budgets.

## Compared strategies

The study compares these defensive methods at equal budgets:

- random defense selection;
- CVSS score priority ordering;
- topology-driven policy segmentation;
- simulation-informed patching;
- simulated-annealing search over patching and segmentation actions.

Each method uses equal budgets of one, two, and three actions. Each method uses
multiple fixed selection seeds.

This page does not prescribe a construction method or a topology generator.

## Outcomes

Mission impact is the primary outcome. The study ranks strategies by expected
mission impact. Blast radius is a secondary safety outcome.

## Runtime measures

The study reports median wall-clock durations for:

- simulation;
- strategy selection;
- total evaluation.

The study takes these measures after warm-up on a fixed documented environment.

## Mission-impact pilot

A mission-impact pilot selects the attack-trial count before the full study.
It reports only measured behavior of the current stylized model.

## Frozen inputs

Before the full study, the study freezes all comparability inputs:

- topology variants;
- graph data;
- metrics;
- strategies;
- budgets;
- selection seeds;
- attack seeds;
- trial count;
- stopping rules.

## Limits

The study adds no directional hypothesis. It makes no claims beyond the
measured stylized models.
