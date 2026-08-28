# Topology-Scale Study Protocol

Question: how does controlled growth in topology size affect simulation,
strategy-selection, and total-evaluation runtime, and the mission-impact ranking
of equal-budget defense strategies?

See the [scope page](../concepts/scope.md) for the research boundary.

## Status

Local rehearsal work informed the cloud-study plan. The cloud study is blocked
until the planned tooling exists: see the
[cloud evaluation tooling plan](cloud-evaluation-tooling-plan.md). The
rehearsal does not support cloud runtime, topology-scale, optimizer-quality, or
strategy-effect claims.

This study uses a manual, manifest-driven process. Each command acts on one
saved manifest or one archive. The system does not include a study batch
runner.

## Size tiers

The study uses three controlled size tiers. A runtime pilot selects their exact
host counts before the full study. Edge counts are generated outputs of the
selected host counts, not inputs.

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

Each tier runs five measured replicas. The study times each accepted replica
and reports the median of the five accepted replicas for every timing metric.
The runner and the analysis record strategy-selection time as plan-selection
time; the names refer to the same measure.

The study takes these measures after warm-up on a fixed documented environment.

## Mission-impact pilot

The mission-impact pilot selects the attack-trial count before the full study.
It chooses the smallest trial count that meets `analysis.pilot.ci_half_width`
for all selected tiers. It reports only measured behavior of the current
stylized model.

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

## Cloud protocol

The cloud study is blocked until the planned tooling is complete. See the
[cloud evaluation tooling plan](cloud-evaluation-tooling-plan.md) and the
[runbook prerequisites](cloud-evaluation-runbook.md#prerequisites).

See the [cloud evaluation runbook](cloud-evaluation-runbook.md) to execute the
measured cloud study. The cloud study extends the manual process below. Run the
diagnostic before it freezes tiers. It records whether growth changes
attack-relevant structure. An unchanged result is evidence, not a failed gate.

Pilot ownership:

- The runtime pilot owns the tier host counts. It selects host counts that fit
  the environment capacity and pass the topology diagnostic.
- The mission-impact pilot owns the common attack-trial count. It runs
  `mix evaluate.analyze --run-id RUN_ID --mode pilot --output pilot.zip` and
  chooses the smallest trial count that meets `analysis.pilot.ci_half_width`
  for all selected tiers.

When the tooling is complete, Mix commands run in a one-off application task
with the deployed application identity, mounted secrets, database access, and
non-conflicting listeners. That task does not exist yet. Do not run host-side
Mix without credentials.

The feasibility input uses a separate manifest reserved for the feasibility
run. It is not tier-runtime evidence. Run it once after the timing runs
complete.

When a source uses the enterprise generator, `source.hosts` counts enterprise
hosts. It excludes the generated internet ingress host.

Before timed cloud runs, confirm the pending migrations and the health of the
application, database, and analysis services.

## Manual Replication Process

1. Keep each source manifest as a versioned JSON file.
2. Import the source manifest with `mix evaluate.import --file PATH`.
3. Run the pilots with the ownership and command recorded under
   [Cloud protocol](#cloud-protocol). Choose the measured tiers and the common
   trial count.
4. For each generated tier, freeze the selected source with
   `mix evaluate.freeze --manifest-id SOURCE --frozen-manifest-id TARGET`.
5. Use the frozen manifest for all warm-up and measured runs. A manifest that
   already names a graph revision needs no freeze step.
6. Run `mix evaluate.warmup --manifest-id TARGET` once. Warm-up is manual
   today; automatic once-per-frozen-manifest warm-up is planned tooling. Do not
   use its result as a timing or outcome sample.
7. Run five new evaluations with
   `mix evaluate.manifest --manifest-id TARGET --output ARCHIVE`. Write one
   archive for each run. The task starts a new run on every invocation. Save the
   printed run ID. Name each archive with its tier, replica number, and run ID.
8. Handle a failed, cancelled, interrupted, corrupt, or missing-archive
   replica. Never resume a timing replica: exclude the run from the timing
   samples, log it, and, after confirming no duplicate execution, start a
   fresh replacement. Stop if the problem recurs or cannot be diagnosed.
9. Use the first timed archive for outcome analysis. Run analysis for every
   accepted archive so each replica produces a runtime summary.
10. Compare each other timed archive with the first one before accepting its
   timing result. A comparison error, including a malformed archive, stops
   acceptance.
11. For each tier, report the median timing values from five accepted runtime
    summaries.

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
an outcome mismatch. A comparison error, including a malformed archive, stops
acceptance. See the [analysis guide](../../evaluation/analysis/README.md) for
the comparison details and how to run it from `evaluation/analysis/`.

## Limits

The study adds no directional hypothesis. It makes no claims beyond the
measured stylized models.
