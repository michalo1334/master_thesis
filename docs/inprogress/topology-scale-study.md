# Topology-Scale Study Protocol

Question: how does controlled growth in topology size affect simulation,
strategy-selection, and total-evaluation runtime, and the mission-impact ranking
of equal-budget defense strategies?

See the [scope page](../concepts/scope.md) for the research boundary.

## Status

This study uses a manual, manifest-driven process. Each command acts on one
saved manifest or one archive. The system does not include a study batch
runner.

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

## Manual Replication Process

1. Keep each source manifest as a versioned JSON file.
2. Import the source manifest with `mix evaluate.import --file PATH`.
3. Run pilots. Choose the measured tiers and the common trial count.
4. For each generated tier, freeze the selected source with
   `mix evaluate.freeze --manifest-id SOURCE --frozen-manifest-id TARGET`.
5. Use the frozen manifest for all warm-up and measured runs. A manifest that
   already names a graph revision needs no freeze step.
6. Run `mix evaluate.warmup --manifest-id TARGET` once. Do not use its result
   as a timing or outcome sample.
7. Run five new evaluations with `mix evaluate.manifest`. Write one archive for
   each run.
8. Exclude interrupted or resumed runs from the timing samples.
9. Use the first timed archive for outcome analysis.
10. Compare each other timed archive with the first one before accepting its
    timing result.

Do not change a measured graph revision or manifest during these runs.

## Replica Check

Run this command from `evaluation/analysis/`:

```sh
uv run network-defense-analysis compare first.zip replica.zip
```

The command checks the manifest, graph, selected plans, attack outcomes,
capability outcomes, pre-attack flow status, host compromises, and non-timing
summary values. It ignores run IDs and timing values. It returns zero when the
outcomes match. It returns one when they differ. Stop the study and investigate
an outcome mismatch.

## Limits

The study adds no directional hypothesis. It makes no claims beyond the
measured stylized models.
