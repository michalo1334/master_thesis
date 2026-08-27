# Evaluation Lifecycle

The evaluation runner executes a saved manifest. It compares how defense
strategies reduce modeled attack impact. It produces deterministic result
artifacts for later statistical analysis.

This page describes the current runner only. The approved topology-scale study
is a research design, not current implementation (see
[scope.md](scope.md)).

## Manifest inputs

A manifest declares everything the runner needs for one evaluation. Validation
and schema live in
[`Contracts.EvaluationManifest`](../../src/lib/network_defense/evaluation/contracts/evaluation_manifest.ex).
Inputs fall into these categories:

- **Scenario source.** The source graph to attack. It is either a persisted
  graph revision or a generated topology.
- **Attacker.** The initial foothold, the host the attack starts from, and the
  maximum attacker attempts per step.
- **Model variants.** The objectives and pre-attack feasibility rules used by
  optimization. Each variant fixes an objective and whether a plan must keep
  mission capability feasible before the attack.
- **Strategies and plans.** The defense strategies to run, each under a
  budget. A plan is one strategy under one budget for one selection seed.
- **Budget.** The maximum number of defense actions a plan may apply. Current
  defensive actions have unit cost, so budget and action count are equal.
- **Trials and iterations.** The attack-trial count per experiment and the
  optional optimizer trials and iterations for simulation-based strategies.
- **Objectives.** The analyzed outcomes, such as blast radius and mission
  impact, plus the comparisons declared for later analysis.
- **Seeds.** Deterministic random inputs for the evaluation.

The authoritative field set, defaults, and allowed values live in the
`EvaluationManifest` contract. Do not read them from this page.

## Seeds for repeatability

A manifest declares seeds so that a run is repeatable. The same declared
inputs produce the same plans and trials. The
[`SeedSchedule`](../../src/lib/network_defense/evaluation/seed_schedule.ex)
derives named child seeds for the distinct streams, so changing one stream
does not disturb another. The entry host for the source graph comes from the
attacker declaration.

## Lifecycle

The runner lifecycle ends when an evaluation run completes. The
[`Evaluator`](../../src/lib/network_defense/evaluation/evaluator.ex) drives the
execution. Export and statistical analysis are explicit follow-on steps.

```mermaid
flowchart TD
    A[Resolve manifest] --> B[Create seed schedule]
    B --> C[Select plans]
    C --> D[Run baseline attack trials]
    D --> E[Run post-defense trials for each plan]
    E --> F[Complete evaluation run]
    R[Restart incomplete evaluation] -.-> A
    F --> G[Export result archive on request]
    G --> H[Run statistical analysis]
```

The runner resolves the manifest source into a graph revision and builds one
seed schedule. It selects every plan before baseline trials begin. It then
runs the baseline attack trials on the source graph, followed by post-defense
trials on each optimized graph revision. The run completes only after every
experiment completes. On request, the system exports a completed run as a
result archive. A separate command starts statistical analysis.

## Resumability and runner commands

A restarted evaluation reuses completed work instead of redoing it. The runner
is idempotent: rerunning does not duplicate completed plans or trials. You can
run a saved manifest with:

- `mix evaluate.manifest --manifest-id ID --output evaluation.zip`

The archive holds the resolved manifest, source graph, plans, and trial
results. For analysis:

- `mix evaluate.analyze --run-id RUN_ID --mode analyze --output analysis.zip`

The [`evaluate.optimization`](../../src/lib/mix/tasks/evaluate.optimization.ex)
task runs a single optimization synchronously and prints a JSON record. The
[`evaluate.manifest`](../../src/lib/mix/tasks/evaluate.manifest.ex) task runs
a whole saved manifest. The
[`evaluate.analyze`](../../src/lib/mix/tasks/evaluate.analyze.ex) task sends a
completed archive to the analysis service.

## Comparable experiments

The shared example in [model-example.md](model-example.md) describes the model
with one client zone, one service zone, one vulnerable service, one credential,
and one mission capability. Use it to reason about one comparable baseline and
one equal-budget post-defense experiment.

The two experiments declare the same inputs: the same scenario source, the
same attacker entry, the same trial count, and the same evaluation seed. The
baseline runs attack trials on the source graph with no defense action. The
post-defense run first selects one plan under the equal action budget, applies
its defense action to form an optimized graph, then runs attack trials on that
graph with the same declared inputs. The two outcomes are comparable because
only the applied plan differs.

Terminology follows [vocabulary.md](vocabulary.md). Statistical analysis,
including comparisons and uncertainty, is described in the
[evaluation analysis README](../../evaluation/analysis/README.md).

## Relationship to the topology-scale study

The lifecycle above is current behavior. The approved three-tier topology-scale
study is designed but not implemented as frozen controlled variants. Current
code supports the baseline scenario and generic topology sources. Do not treat
this lifecycle as a description of that study.
